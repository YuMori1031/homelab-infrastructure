#!/usr/bin/python3
import json,os,re,subprocess,tempfile,time
from pathlib import Path
from datetime import datetime, timezone, timedelta
OUT=Path('/var/lib/homelab-vpn-monitor/status.json')
STATE=Path('/var/lib/homelab-vpn-monitor/remote-access-state.json')
SITE_STATE=Path('/var/lib/homelab-vpn-monitor/site-to-site-state.json')
SITE_EVENT_STATE=Path('/var/lib/homelab-vpn-monitor/site-to-site-event-state.json')
REMOTE_EVENT_STATE=Path('/var/lib/homelab-vpn-monitor/remote-access-event-state.json')
SITE_EVENT_LOG=Path('/var/log/homelab-vpn-monitor/site-to-site-events.log')
REMOTE_EVENT_LOG=Path('/var/log/homelab-vpn-monitor/remote-access-events.log')
EVENT_TZ=timezone(timedelta(hours=9))
REQUIRED={'site_a':('site_a-site',{'site_a-aws','site_a-site_b','site_a-remote-access'}),'site_b':('site_b-site',{'site_b-aws','site_b-site_a','site_b-remote-access'})}
def collect(text):
 records=[];current=None
 for line in text.splitlines():
  if not line.strip():continue
  if not line.startswith(' '):
   match=re.match(r'^([^:]+): #\d+, ([A-Z_]+), IKEv[12],',line)
   if not match:raise ValueError('unexpected SA header')
   current={'name':match[1],'state':match[2],'children':set()};records.append(current)
  elif re.match(r'^  \S+: #',line):
   match=re.match(r'^  ([^:]+): #\d+, reqid \d+, ([A-Z_]+),',line)
   if not match or current is None:raise ValueError('unexpected child header')
   if match[2]=='INSTALLED':current['children'].add(match[1])
 sites={}
 for site,(name,required) in REQUIRED.items():
  valid=[r for r in records if r['name']==name and r['state']=='ESTABLISHED']
  children=set().union(*(r['children'] for r in valid)) if valid else set()
  sites[site]={'status':'normal' if valid and required<=children else 'abnormal','ike_established':bool(valid),'children_installed':{n:n in children for n in sorted(required)}}
 return sites
def load_site_state():
    try:
        data = json.loads(SITE_STATE.read_text())
        if not isinstance(data, dict):
            return {}
        return {key: value for key, value in data.items()
                if key in REQUIRED and isinstance(value, int) and value > 0}
    except Exception:
        return {}

def save_site_state(state):
    fd, path = tempfile.mkstemp(prefix='.site-to-site-state-', dir=SITE_STATE.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump(state, f, separators=(',', ':'))
            f.flush(); os.fsync(f.fileno())
        os.replace(path, SITE_STATE)
    finally:
        if os.path.exists(path):
            os.unlink(path)

def add_site_times(sites):
    previous = load_site_state()
    now = int(time.time())
    state = {}
    enriched = {}
    for site, details in sites.items():
        details = dict(details)
        if details.get('status') == 'normal':
            connected_since = previous.get(site, now)
            details['connected_since'] = connected_since
            details['elapsed_seconds'] = max(0, now - connected_since)
            state[site] = connected_since
        else:
            details['connected_since'] = None
            details['elapsed_seconds'] = None
        enriched[site] = details
    save_site_state(state)
    return enriched

# Read-only VICI list-sas support. No configuration or SA-control commands.
import socket, struct, ipaddress

IDENTITY_LABELS = {}

def _vici_decode(data):
    pos = 0
    root = {}
    stack = [root]
    current_list = None
    def take(n):
        nonlocal pos
        if pos+n > len(data):
            raise ValueError('truncated VICI message')
        result = data[pos:pos+n]
        pos += n
        return result
    def name():
        return take(take(1)[0]).decode('utf-8')
    def value():
        return take(struct.unpack('!H', take(2))[0]).decode('utf-8')
    while pos < len(data):
        kind = take(1)[0]
        if kind == 1:
            key = name()
            if key in stack[-1]:
                raise ValueError('duplicate VICI section')
            child = {}; stack[-1][key] = child; stack.append(child)
        elif kind == 2:
            if len(stack) <= 1:
                raise ValueError('unbalanced VICI section')
            stack.pop()
        elif kind == 3:
            key = name(); stack[-1][key] = value()
        elif kind == 4:
            key = name(); current_list = []; stack[-1][key] = current_list
        elif kind == 5:
            if current_list is None:
                raise ValueError('unexpected VICI list entry')
            current_list.append(value())
        elif kind == 6:
            current_list = None
        else:
            raise ValueError('unknown VICI data type')
    if len(stack) != 1 or current_list is not None:
        raise ValueError('incomplete VICI message')
    return root

def read_remote_sas():
    deadline = time.monotonic()+10
    records = []
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(10)
        sock.connect('/run/example-vici.sock')
        def read_exact(n):
            result = bytearray()
            while len(result) < n:
                remaining = deadline-time.monotonic()
                if remaining <= 0:
                    raise TimeoutError('VICI read deadline')
                sock.settimeout(remaining)
                part = sock.recv(n-len(result))
                if not part:
                    raise ValueError('VICI connection closed')
                result.extend(part)
            return bytes(result)
        def receive():
            size = struct.unpack('!I', read_exact(4))[0]
            if size < 1 or size > 4*1024*1024:
                raise ValueError('invalid VICI packet size')
            return read_exact(size)
        def send(payload):
            sock.sendall(struct.pack('!I', len(payload))+payload)
        send(b'\x03\x07list-sa')
        if receive() != b'\x05':
            raise ValueError('VICI event registration failed')
        # Only the read-only list-sas command, restricted to remote-access.
        send(b'\x00\x08list-sas\x03\x03ike\x00\x0dremote-access')
        while True:
            packet = receive()
            if packet[0] == 7:
                n = packet[1]
                if packet[2:2+n] != b'list-sa':
                    raise ValueError('unexpected VICI event')
                event = _vici_decode(packet[2+n:])
                for connection, record in event.items():
                    if connection == 'remote-access':
                        records.append(record)
            elif packet[0] == 1:
                response = _vici_decode(packet[1:])
                if response.get('success', 'yes') != 'yes':
                    raise ValueError('VICI query failed')
                return records
            else:
                raise ValueError('unexpected VICI reply')

def load_remote_state():
    try:
        data = json.loads(STATE.read_text())
        if not isinstance(data, dict): return {}
        out = {}
        for key, value in data.items():
            if isinstance(key, str) and isinstance(value, int) and value > 0:
                out[key] = value
        return out
    except Exception:
        return {}

def save_remote_state(state):
    fd, path = tempfile.mkstemp(prefix='.remote-access-state-', dir=STATE.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump(state, f, separators=(',', ':'))
            f.flush(); os.fsync(f.fileno())
        os.replace(path, STATE)
    finally:
        if os.path.exists(path): os.unlink(path)

def summarize_remote(records, labels=None):
    labels = IDENTITY_LABELS if labels is None else labels
    now = int(time.time())
    previous = load_remote_state()
    sessions = {}
    for record in records:
        if record.get('state') != 'ESTABLISHED':
            continue
        children = record.get('child-sas', {})
        if not any(c.get('name') == 'remote-access' and c.get('state') == 'INSTALLED'
                   for c in children.values()):
            continue
        identity = record.get('remote-id')
        if not identity:
            raise ValueError('connected session missing identity')
        ips = record.get('remote-vips', [])
        if not ips:
            raise ValueError('connected session missing virtual IP')
        for address in ips:
            ip = ipaddress.ip_address(address)
            if ip.version != 4 or ip not in ipaddress.ip_network('10.10.255.0/24'):
                raise ValueError('unexpected virtual IP')
            # Raw identities are used only in memory and the private label mapping.
            key = identity + '|' + str(ip)
            connected_since = previous.get(key, now)
            sessions[key] = {
                'user': identity,
                'virtual_ip': str(ip), 'status': 'connected',
                'connected_since': connected_since,
                'elapsed_seconds': max(0, now - connected_since)
            }
    save_remote_state({key: value['connected_since'] for key, value in sessions.items()})
    values = sorted(sessions.values(), key=lambda r: (r['user'], ipaddress.ip_address(r['virtual_ip'])))
    return {'collection_status': 'ok', 'connected_count': len(values), 'sessions': values}

def collect_remote():
    try:
        return summarize_remote(read_remote_sas())
    except Exception:
        # Never include raw response data or exception strings in output/logs.
        return {'collection_status': 'error', 'connected_count': None, 'sessions': []}



def load_event_state(path):
    try:
        data=json.loads(path.read_text())
        return data if isinstance(data, (dict, list)) else None
    except Exception:
        return None

def save_event_state(path, data):
    fd, tmp = tempfile.mkstemp(prefix='.'+path.name+'-', dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            json.dump(data, f, separators=(',', ':'))
            f.flush(); os.fsync(f.fileno())
        os.replace(tmp, path)
        d=os.open(path.parent, os.O_DIRECTORY); os.fsync(d); os.close(d)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def _log_field(value):
    return str(value).replace('|','_').replace('\r','_').replace('\n','_')

def append_event(path, fields):
    line='|'.join(_log_field(v) for v in fields)
    with path.open('a', encoding='utf-8') as f:
        f.write(line+'\n'); f.flush(); os.fsync(f.fileno())

def event_time(now):
    return datetime.fromtimestamp(now, EVENT_TZ).strftime('%Y/%m/%d %H:%M:%S')

def record_site_events(sites):
    current={site: details.get('status') for site, details in sites.items()}
    previous=load_event_state(SITE_EVENT_STATE)
    if not isinstance(previous, dict) or any(site not in previous for site in REQUIRED):
        save_event_state(SITE_EVENT_STATE, {site: current.get(site) for site in REQUIRED})
        return
    now=event_time(int(time.time()))
    labels={'site_a':'Site A','site_b':'Site B'}
    for site in REQUIRED:
        old,new=previous.get(site),current.get(site)
        if old=='normal' and new=='abnormal':
            append_event(SITE_EVENT_LOG, (now, labels[site], '切断'))
        elif old=='abnormal' and new=='normal':
            append_event(SITE_EVENT_LOG, (now, labels[site], '接続'))
    save_event_state(SITE_EVENT_STATE, {site: current.get(site) for site in REQUIRED})

def record_remote_events(remote):
    if remote.get('collection_status') != 'ok':
        return
    current={}
    for session in remote.get('sessions', []):
        user=session.get('user'); vip=session.get('virtual_ip')
        if not isinstance(user,str) or not isinstance(vip,str):
            return
        current[user+'|'+vip]={'user':user,'virtual_ip':vip}
    previous=load_event_state(REMOTE_EVENT_STATE)
    if not isinstance(previous, dict):
        save_event_state(REMOTE_EVENT_STATE, current)
        return
    now=event_time(int(time.time()))
    for key in sorted(set(current)-set(previous)):
        item=current[key]; append_event(REMOTE_EVENT_LOG, (now,item['user'],item['virtual_ip'],'接続'))
    for key in sorted(set(previous)-set(current)):
        item=previous[key]
        if isinstance(item,dict) and isinstance(item.get('user'),str) and isinstance(item.get('virtual_ip'),str):
            append_event(REMOTE_EVENT_LOG, (now,item['user'],item['virtual_ip'],'切断'))
    save_event_state(REMOTE_EVENT_STATE, current)

def main():
 try:
  result=subprocess.run(['/usr/sbin/swanctl','--list-sas'],capture_output=True,text=True,timeout=15,check=True)
  sites=add_site_times(collect(result.stdout))
  record_site_events(sites)
 except Exception:
  sites={k:{'status':'unknown','connected_since':None,'elapsed_seconds':None} for k in REQUIRED}
 remote=collect_remote()
 record_remote_events(remote)
 data={'version':1,'collected_at':int(time.time()),'sites':sites,'remote_access':remote}
 fd,path=tempfile.mkstemp(prefix='.status-',dir=OUT.parent)
 try:
  os.fchmod(fd,0o640)
  with os.fdopen(fd,'w') as f:json.dump(data,f,separators=(',',':'));f.flush();os.fsync(f.fileno())
  os.replace(path,OUT)
  d=os.open(OUT.parent,os.O_DIRECTORY);os.fsync(d);os.close(d)
 finally:
  if os.path.exists(path):os.unlink(path)
if __name__=='__main__':main()
