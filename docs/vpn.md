# VPN Design

The example uses strongSwan for AWS ↔ Site A, AWS ↔ Site B, and certificate-authenticated Remote Access clients. Addresses and names are documentation values. Remote Access uses `vpn.example.com`, pool `10.10.255.0/24`, and local TS `10.10.0.0/16`.

PKI scripts cover client/site certificate issue, revocation, and CRL generation. Private key material is external to this artifact.
