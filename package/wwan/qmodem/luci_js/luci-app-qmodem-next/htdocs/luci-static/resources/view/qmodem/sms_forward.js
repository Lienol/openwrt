'use strict';
'require view';
'require form';
'require uci';
'require ui';
'require qmodem.qmodem as qmodem';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('sms_forwarder'),
			qmodem.getModemSections()
		]);
	},

	render: function(data) {
		var modems = data[1];
		var m, s, o;

		m = new form.Map('sms_forwarder', _('SMS Forwarder Configuration'),
			_('Configure SMS forwarding to various notification services'));

		// Global settings
		s = m.section(form.NamedSection, 'sms_forward', 'sms_forward', _('Global Settings'));

		o = s.option(form.Flag, 'enable', _('Enable SMS Forwarder'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.ListValue, 'log_level', _('Log Level'));
		o.value('error', _('Error'));
		o.value('warn', _('Warning'));
		o.value('info', _('Info'));
		o.value('debug', _('Debug'));
		o.default = 'info';

		// Forward instances
		s = m.section(form.GridSection, 'sms_forward_instance', _('Forward Instances'),
			_('Configure SMS forwarding instances for different modems and services'));

		s.addremove = true;
		s.anonymous = true;
		s.sortable = true;

		o = s.option(form.Flag, 'enable', _('Enable'));
		o.default = '0';
		o.editable = true;

		o = s.option(form.ListValue, 'modem_cfg', _('Modem Config'));
		o.rmempty = false;
		modems.forEach(function(modem) {
			if (modem.enabled) {
				o.value(modem.id, modem.name);
			}
		});

		o = s.option(form.Value, 'poll_interval', _('Poll Interval (seconds)'));
		o.datatype = 'range(5,600)';
		o.default = '30';
		o.placeholder = '30';

		o = s.option(form.ListValue, 'api_type', _('API Type'));
		o.value('tgbot', _('Telegram Bot'));
		o.value('webhook', _('Webhook'));
		o.value('serverchan', _('ServerChan'));
		o.value('pushdeer', _('PushDeer'));
		o.value('feishu', _('Feishu Bot'));
		o.value('custom', _('Custom Script'));
		o.default = 'webhook';

		// Modal button to configure API
		o = s.option(form.Button, '_configure', _('Configure'));
		o.inputtitle = _('Configure API');
		o.inputstyle = 'apply';
		o.onclick = L.bind(function(ev, section_id) {
			this.showConfigModal(section_id, modems);
		}, this);

		return m.render();
	},

	showConfigModal: function(section_id, modems) {
		var self = this;
		var api_type = uci.get('sms_forwarder', section_id, 'api_type') || 'webhook';
		var api_config_str = uci.get('sms_forwarder', section_id, 'api_config') || '{}';
		var api_config = {};
		
		try {
			api_config = JSON.parse(api_config_str);
		} catch(e) {
			api_config = {};
		}

		var modalBody = [];
		var inputs = {};

		modalBody.push(E('p', { 'class': 'alert-message info' }, 
			_('Configure the API settings for ') + api_type));

		// Telegram Bot configuration
		if (api_type === 'tgbot') {
			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Bot Token')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.bot_token = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.bot_token || '',
						'placeholder': '123456:ABC-DEF1234ghIkl'
					})
				])
			]));

			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Chat ID')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.chat_id = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.chat_id || '',
						'placeholder': '123456789'
					})
				])
			]));
		}
		// Webhook configuration
		else if (api_type === 'webhook') {
			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Webhook URL')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.webhook_url = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.webhook_url || '',
						'placeholder': 'https://example.com/webhook'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('Supports placeholders: {SENDER}, {CONTENT}, {TIME}'))
				])
			]));

			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Request Method')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.request_method = E('select', { 'class': 'cbi-input-select' }, [
						E('option', { 'value': 'GET', 'selected': (api_config.request_method === 'GET' || !api_config.request_method) }, 'GET'),
						E('option', { 'value': 'POST', 'selected': (api_config.request_method === 'POST') }, 'POST')
					])
				])
			]));

			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Message Format (optional)')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.format = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.format || '',
						'placeholder': '{"sender":"{SENDER}","time":"{TIME}","content":"{CONTENT}"}'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('Custom format using placeholders: {SENDER}, {CONTENT}, {TIME}'))
				])
			]));

			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Headers (optional)')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.headers = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.headers || '',
						'placeholder': 'Authorization: Bearer token'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('HTTP headers, one per line'))
				])
			]));
		}
		// ServerChan configuration
		else if (api_type === 'serverchan') {
			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Token')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.token = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.token || '',
						'placeholder': 'SCT123456TCxyz...'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('ServerChan API token from https://sctapi.ftqq.com'))
				])
			]));

			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Channel (optional)')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.channel = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.channel || '',
						'placeholder': '9|66'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('Message channel, use | to separate multiple channels'))
				])
			]));

			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Hide IP')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.noip = E('input', {
						'type': 'checkbox',
						'checked': api_config.noip === '1' || api_config.noip === true
					})
				])
			]));

			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('OpenID (optional)')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.openid = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.openid || '',
						'placeholder': 'openid1,openid2'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('OpenID for message forwarding, use comma to separate multiple IDs'))
				])
			]));
		}
		// PushDeer configuration
		else if (api_type === 'pushdeer') {
			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Push Key')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.pushkey = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.pushkey || '',
						'placeholder': 'PDU123456T...'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('PushDeer Push Key from http://pushdeer.com'))
				])
			]));

			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Server (optional)')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.server = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.server || '',
						'placeholder': 'https://api2.pushdeer.com'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('Custom PushDeer API endpoint, leave empty to use default'))
				])
			]));
		}
		// Feishu configuration
		else if (api_type === 'feishu') {
			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Webhook URL')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.webhook_url = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.webhook_url || '',
						'placeholder': 'https://open.feishu.cn/open-apis/bot/v2/hook/xxxxx'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('Feishu webhook URL from your bot configuration'))
				])
			]));
		}
		// Custom script configuration
		else if (api_type === 'custom') {
			modalBody.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Script Path')),
				E('div', { 'class': 'cbi-value-field' }, [
					inputs.script_path = E('input', {
						'type': 'text',
						'class': 'cbi-input-text',
						'value': api_config.script_path || '',
						'placeholder': '/usr/share/sms_forwarder/sms_forward_custom.sh'
					}),
					E('div', { 'class': 'cbi-value-description' }, 
						_('Path to custom forwarding script. Script receives SMS_SENDER, SMS_TIME, SMS_CONTENT environment variables'))
				])
			]));
		}

		ui.showModal(_('Configure API Settings'), [
			E('div', { 'class': 'cbi-section' }, modalBody),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn cbi-button-neutral',
					'click': ui.hideModal
				}, _('Cancel')),
				E('button', {
					'class': 'btn cbi-button-positive',
					'click': function() {
						self.saveApiConfig(section_id, api_type, inputs);
					}
				}, _('Save'))
			])
		]);
	},

	saveApiConfig: function(section_id, api_type, inputs) {
		var config = {};

		if (api_type === 'tgbot') {
			config.bot_token = inputs.bot_token.value.trim();
			config.chat_id = inputs.chat_id.value.trim();
		} else if (api_type === 'webhook') {
			config.webhook_url = inputs.webhook_url.value.trim();
			config.request_method = inputs.request_method.value;
			if (inputs.format.value.trim()) {
				config.format = inputs.format.value.trim();
			}
			if (inputs.headers.value.trim()) {
				config.headers = inputs.headers.value.trim();
			}
		} else if (api_type === 'serverchan') {
			config.token = inputs.token.value.trim();
			if (inputs.channel.value.trim()) {
				config.channel = inputs.channel.value.trim();
			}
			config.noip = inputs.noip.checked ? '1' : '0';
			if (inputs.openid.value.trim()) {
				config.openid = inputs.openid.value.trim();
			}
		} else if (api_type === 'pushdeer') {
			config.pushkey = inputs.pushkey.value.trim();
			if (inputs.server.value.trim()) {
				config.server = inputs.server.value.trim();
			}
		} else if (api_type === 'feishu') {
			config.webhook_url = inputs.webhook_url.value.trim();
		} else if (api_type === 'custom') {
			config.script_path = inputs.script_path.value.trim();
		}

		var config_str = JSON.stringify(config);
		uci.set('sms_forwarder', section_id, 'api_config', config_str);

		ui.hideModal();
		ui.addNotification(null, E('p', _('API configuration saved. Remember to save & apply changes.')), 'info');
	}
});
