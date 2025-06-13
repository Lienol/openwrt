'use strict';
'require rpc';
'require form';
'require network';

var callFileList = rpc.declare({
	object: 'file',
	method: 'list',
	params: [ 'path' ],
	expect: { entries: [] },
	filter: function(list, params) {
		var rv = [];
		for (var i = 0; i < list.length; i++)
			if (list[i].name.match(/^cdc-wdm/))
				rv.push(params.path + list[i].name);
		return rv.sort();
	}
});

network.registerPatternVirtual(/^quectel-.+$/);
network.registerErrorCode('CALL_FAILED', _('Call failed'));
network.registerErrorCode('NO_CID',      _('Unable to obtain client ID'));
network.registerErrorCode('PLMN_FAILED', _('Setting PLMN failed'));

return network.registerProtocol('quectel', {
	getI18n: function() {
		return _('Quectel Cellular');
	},

	getIfname: function() {
		return this._ubus('l3_device') || 'quectel-%s'.format(this.sid);
	},

	getOpkgPackage: function() {
		return 'quectel-cm';
	},

	isFloating: function() {
		return true;
	},

	isVirtual: function() {
		return true;
	},

	getDevices: function() {
		return null;
	},

	containsDevice: function(ifname) {
		return (network.getIfnameOf(ifname) == this.getIfname());
	},

	renderFormOptions: function(s) {
		var dev = this.getL3Device() || this.getDevice(), o, apn, apnv6;

		o = s.taboption('general', form.Value, '_modem_device', _('Modem device'));
		o.ucioption = 'device';
		o.rmempty = false;
		o.load = function(section_id) {
			return callFileList('/dev/').then(L.bind(function(devices) {
				for (var i = 0; i < devices.length; i++)
					this.value(devices[i]);
				return form.Value.prototype.load.apply(this, [section_id]);
			}, this));
		};

		o = s.taboption('general', form.Flag, 'multiplexing', _('Use IP Multiplexing'));
		o.default = o.disabled;

		apn = s.taboption('general', form.Value, 'apn', _('APN'));
		apn.depends('pdptype', 'ipv4v6');
		apn.depends('pdptype', 'ipv4');
		apn.validate = function(section_id, value) {
			if (value == null || value == '')
				return true;

			if (!/^[a-zA-Z0-9\-.]*[a-zA-Z0-9]$/.test(value))
				return _('Invalid APN provided');

			return true;
		};

		apnv6 = s.taboption('general', form.Value, 'apnv6', _('IPv6 APN'));
		apnv6.depends({ pdptype: 'ipv4v6', multiplexing: '1' });
		apnv6.depends({ pdptype: 'ipv6', multiplexing: '1' });
		apnv6.validate = function(section_id, value) {
			if (value == null || value == '')
				return true;

			if (!/^[a-zA-Z0-9\-.]*[a-zA-Z0-9]$/.test(value))
				return _('Invalid APN provided');

			var apn_value = apn.formvalue(section_id);

			if (value.toLowerCase() === apn_value.toLowerCase())
				return _('APN IPv6 must be different from APN');
	
			return true;
		};

		o = s.taboption('general', form.Value, 'pincode', _('PIN'));
		o.datatype = 'and(uinteger,minlength(4),maxlength(8))';

		o = s.taboption('general', form.ListValue, 'auth', _('Authentication Type'));
		o.value('mschapv2', 'MsChapV2');
		o.value('pap', 'PAP');
		o.value('chap', 'CHAP');
		o.value('none', 'NONE');
		o.default = 'none';

		o = s.taboption('general', form.Value, 'username', _('PAP/CHAP username'));
		o.depends('auth', 'pap');
		o.depends('auth', 'chap');
		o.depends('auth', 'mschapv2');

		o = s.taboption('general', form.Value, 'password', _('PAP/CHAP password'));
		o.depends('auth', 'pap');
		o.depends('auth', 'chap');
		o.depends('auth', 'mschapv2');
		o.password = true;

		o = s.taboption('advanced', form.Value, 'delay', _('Modem init timeout'),
			_('Maximum amount of seconds to wait for the modem to become ready'));
		o.placeholder = '5';
		o.datatype    = 'min(1)';

		o = s.taboption('advanced', form.Value, 'mtu', _('Override MTU'));
		o.placeholder = dev ? (dev.getMTU() || '1500') : '1500';
		o.datatype    = 'max(9200)';

		o = s.taboption('advanced', form.Value, 'pdnindex', _('PDN index'));
		o.depends({ pdptype: 'ipv4v6', multiplexing: '1' });
		o.depends({ pdptype: 'ipv4', multiplexing: '1' });
		o.placeholder = '1';
		o.datatype = 'and(uinteger,min(1),max(7))';

		o = s.taboption('advanced', form.Value, 'pdnindexv6', _('IPv6 PDN index'));
		o.depends({ pdptype: 'ipv4v6', multiplexing: '1' });
		o.depends({ pdptype: 'ipv6', multiplexing: '1' });
		o.placeholder = '2';
		o.datatype = 'and(uinteger,min(1),max(7))';

		o = s.taboption('general', form.ListValue, 'pdptype', _('PDP Type'));
		o.value('ipv4v6', 'IPv4/IPv6');
		o.value('ipv4', 'IPv4');
		o.value('ipv6', 'IPv6');
		o.default = 'ipv4v6';

		o = s.taboption('advanced', form.Flag, 'defaultroute', _('Use default gateway'),
			_('If unchecked, no default route is configured'));
		o.default = o.enabled;

		o = s.taboption('advanced', form.Value, 'metric', _('Use gateway metric'));
		o.placeholder = '0';
		o.datatype = 'uinteger';
		o.depends('defaultroute', '1');

        o = s.taboption('advanced', form.DynamicList, 'cell_lock_4g', _('4G Cell ID Lock'));
        o.datatype = 'string';
        o.placeholder = _('<PCI>,<EARFCN>');

		o.validate = function(section_id, value) {
            if (value === null || value === '')
                return true;

            var parts = value.split(',');
            if (parts.length !== 2)
                return _('Must be two values separated by a comma(,)');

            var isUnsignedInteger = function(str) {
                return /^\d+$/.test(str);
            };
            
            if (!isUnsignedInteger(parts[0]))
                return _('Invalid PCI!');
            
            if (!isUnsignedInteger(parts[1]))
                return _('Invalid EARFCN!');

            return true;
        };
	}
});
