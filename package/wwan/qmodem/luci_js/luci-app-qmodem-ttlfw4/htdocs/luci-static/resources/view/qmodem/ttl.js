'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';

var callInitAction = rpc.declare({
	object: 'luci',
	method: 'setInitAction',
	params: ['name', 'action'],
	expect: { result: false }
});

var callRcStatus = rpc.declare({
	object: 'rc',
	method: 'list',
	params: ['name'],
	expect: { }
});

return view.extend({
	load: function() {
		var self = this;
		return Promise.all([
			uci.load('qmodem_ttl'),
		]).then(function(results) {
			return results;
		});
	},

	render: function() {
		var m, s, o;
		var self = this;

		m = new form.Map('qmodem_ttl', _('TTL Configuration'),
			_('Configure TTL/Hop Limit settings to modify outgoing packet TTL values. This can help bypass carrier restrictions on tethering.'));

		// Global TTL Configuration
		s = m.section(form.NamedSection, 'main', 'main', _('Global TTL Settings'));
		s.anonymous = true;

		// Enable TTL modification
		o = s.option(form.Flag, 'enable', _('Enable TTL Modification'));
		o.default = '0';
		o.rmempty = false;
		o.description = _('Enable or disable TTL/Hop Limit modification for outgoing packets.');

		// TTL Value
		o = s.option(form.Value, 'ttl', _('TTL Value'));
		o.datatype = 'range(1,255)';
		o.default = '64';
		o.placeholder = '64';
		o.description = _('Set the TTL (Time To Live) value for IPv4 packets and Hop Limit for IPv6 packets. Common values: 64 (Linux default), 128 (Windows default).');

		// Warning section
		s = m.section(form.NamedSection, 'main', 'main', _('Important Notes'));
		s.anonymous = true;

		var warning = s.option(form.DummyValue, '_warning');
		warning.rawhtml = true;
		warning.cfgvalue = function() {
			return E('div', { 'class': 'cbi-value-description' }, [
				E('p', { 'style': 'color: #c00; font-weight: bold;' }, _('Warning:')),
				E('ul', {}, [
					E('li', {}, _('Enabling TTL modification will disable hardware flow offloading for proper packet modification.')),
					E('li', {}, _('This may affect network performance on some devices.')),
					E('li', {}, _('NSS ECM, SFE, and other acceleration modules will be disabled when TTL modification is active.')),
					E('li', {}, _('Settings will take effect after saving and applying changes.'))
				])
			]);
		};

		return m.render();
	},
});
