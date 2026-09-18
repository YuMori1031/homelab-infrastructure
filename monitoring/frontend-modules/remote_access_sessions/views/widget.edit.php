<?php declare(strict_types = 0);
$form = new CWidgetFormView($data);
$form->addField(new CWidgetFieldMultiSelectItemView($data['fields']['itemid']))->show();
