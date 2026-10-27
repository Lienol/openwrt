'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require qmodem.qmodem as qmodem';
'require dom';
'require poll';

var callInitAction = rpc.declare({
	object: 'luci',
	method: 'setInitAction',
	params: ['name', 'action'],
	expect: { result: false }
});

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('qmodem'),
			qmodem.rcStatus('qmodem_network')
		]).then(L.bind(function(results) {
			this.rcStatusData = results[1];
			
			// Load connection status for all modem devices
			var sections = uci.sections('qmodem', 'modem-device');
			var statusPromises = sections.map(function(section) {
				return qmodem.getConnectStatus(section['.name'])
					.then(function(status) {
						return { section_id: section['.name'], status: status };
					})
					.catch(function(err) {
						return { section_id: section['.name'], status: null };
					});
			});
			
			return Promise.all(statusPromises).then(L.bind(function(statuses) {
				this.connectionStatusData = {};
				statuses.forEach(L.bind(function(item) {
					this.connectionStatusData[item.section_id] = item.status;
				}, this));
				return results;
			}, this));
		}, this));
	},

	render: function() {
		var m, s, o;

		m = new form.Map('qmodem', _('QModem Configuration'));

		// Global Dial Configuration
		s = m.section(form.NamedSection, 'main', 'main', _('Global Configuration'));

		o = s.option(form.Flag, 'enable_dial', _('Enable Dial (Global)'));
		o.default = '1';
		o.rmempty = false;

		// QModem network RC status and control
		var rcStatus = s.option(form.DummyValue, '_rc_status', _('QModem Network'));
		rcStatus.rawhtml = true;
		rcStatus.cfgvalue = L.bind(function() {
			var status = this.rcStatusData && this.rcStatusData.qmodem_network ? this.rcStatusData.qmodem_network : null;
			
			if (!status) {
				return E('div', { id: 'rc-status-container' }, [
					E('span', {}, _('Failed to load status'))
				]);
			}
			
			var enabled = status.enabled === true || status.enabled === 'true';
			var running = status.running === true || status.running === 'true';
			
			return E('div', { id: 'rc-status-container' }, [
				E('span', {}, _('Enabled') + ': ' + (enabled ? _('Yes') : _('No'))),
				E('span', { 'style': 'margin-left: 12px;' }, _('Running') + ': ' + (running ? _('Yes') : _('No')))
			]);
		}, this);

		var rcControl = s.option(form.DummyValue, '_rc_control', _('Control'));
		rcControl.rawhtml = true;
		rcControl.cfgvalue = L.bind(function() {
			var status = this.rcStatusData && this.rcStatusData.qmodem_network ? this.rcStatusData.qmodem_network : null;
			var enabled = status ? (status.enabled === true || status.enabled === 'true') : false;
			var running = status ? (status.running === true || status.running === 'true') : false;
			
			var buttons = [];
			
			// Running control: show Start if not running, show Stop and Restart if running
			if (!running) {
				buttons.push(
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'id': 'rc-start-button',
						'click': ui.createHandlerFn(this, function() {
							var self = this;
							return callInitAction('qmodem_network', 'start')
								.then(function() {
									ui.addNotification(null, E('p', _('QModem Network started successfully')));
									return self.updateRcStatus();
								})
								.catch(function(err) {
									ui.addNotification(null, E('p', _('Failed to start QModem Network: ') + err.message), 'error');
									return self.updateRcStatus();
								});
						})
					}, _('Start'))
				);
			} else {
				buttons.push(
					E('button', {
						'class': 'cbi-button cbi-button-reset',
						'id': 'rc-stop-button',
						'click': ui.createHandlerFn(this, function() {
							var self = this;
							return callInitAction('qmodem_network', 'stop')
								.then(function() {
									ui.addNotification(null, E('p', _('QModem Network stopped successfully')));
									return self.updateRcStatus();
								})
								.catch(function(err) {
									ui.addNotification(null, E('p', _('Failed to stop QModem Network: ') + err.message), 'error');
									return self.updateRcStatus();
								});
						})
					}, _('Stop'))
				);
				buttons.push(
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'id': 'rc-restart-button',
						'click': ui.createHandlerFn(this, function() {
							var self = this;
							return callInitAction('qmodem_network', 'restart')
								.then(function() {
									ui.addNotification(null, E('p', _('QModem Network restarted successfully')));
									return self.updateRcStatus();
								})
								.catch(function(err) {
									ui.addNotification(null, E('p', _('Failed to restart QModem Network: ') + err.message), 'error');
									return self.updateRcStatus();
								});
						})
					}, _('Restart'))
				);
			}
			
			buttons.push(E('span', { 'style': 'margin: 0 8px;' }, ' | '));

			// Enabled control: show Enable if not enabled, show Disable if enabled
			if (!enabled) {
				buttons.push(
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'id': 'rc-enable-button',
						'click': ui.createHandlerFn(this, function() {
							var self = this;
							return callInitAction('qmodem_network', 'enable')
								.then(function() {
									ui.addNotification(null, E('p', _('QModem Network enabled successfully')));
									return self.updateRcStatus();
								})
								.catch(function(err) {
									ui.addNotification(null, E('p', _('Failed to enable QModem Network: ') + err.message), 'error');
									return self.updateRcStatus();
								});
						})
					}, _('Enable'))
				);
			} else {
				buttons.push(
					E('button', {
						'class': 'cbi-button cbi-button-negative',
						'id': 'rc-disable-button',
						'click': ui.createHandlerFn(this, function() {
							var self = this;
							return callInitAction('qmodem_network', 'disable')
								.then(function() {
									ui.addNotification(null, E('p', _('QModem Network disabled successfully')));
									return self.updateRcStatus();
								})
								.catch(function(err) {
									ui.addNotification(null, E('p', _('Failed to disable QModem Network: ') + err.message), 'error');
									return self.updateRcStatus();
								});
						})
					}, _('Disable'))
				);
			}
			
			return E('div', { id: 'rc-control-container' }, buttons);
		}, this);

	// Dial Configuration Section (Per-Modem)
	s = m.section(form.GridSection, 'modem-device', _('Dial Configuration'));
	s.anonymous = false;
	s.addremove = false;
	s.modaltitle = L.bind(function(section_id) {
		var name = uci.get('qmodem', section_id, 'name');
		var alias = uci.get('qmodem', section_id, 'alias');
		return _('Dial Configuration') + ': ' + (alias || name || section_id);
	}, this);

	// Connection Status Indicator
	o = s.option(form.DummyValue, '_status_indicator', _('Status'));
	o.rawhtml = true;
	o.editable = true;
	o.width = '60px';
	o.cfgvalue = L.bind(function(section_id) {
		var color = '#999'; // Gray (default/loading)
		var title = _('Loading...');
		
		// Use preloaded data if available
		if (this.connectionStatusData && this.connectionStatusData[section_id]) {
			var result = this.connectionStatusData[section_id];
			if (result && result.connection_status !== undefined) {
				var status = result.connection_status.toString().toLowerCase();
				if (status === 'yes' || status === 'connected' || status === '1' || status === 'true' || status === true) {
					color = '#00FF00'; // Green (connected)
					title = _('Connected');
				} else if (status === 'no' || status === 'disconnected' || status === '0' || status === 'false' || status === false) {
					color = '#FF0000'; // Red (disconnected)
					title = _('Disconnected');
				} else {
					color = '#FFA500'; // Yellow (unknown)
					title = _('Unknown');
				}
			}
		}
		
		return E('div', {
			'id': 'status-indicator-' + section_id,
			'style': 'text-align: center;'
		}, [
			E('span', {
				'style': 'display: inline-block; width: 12px; height: 12px; border-radius: 50%; background-color: ' + color + ';',
				'title': title
			})
		]);
	}, this);

	o = s.option(form.Flag, 'enable_dial', _('Enable Dial'));
		o.default = '0';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.DummyValue, 'name', _('Modem Model'));
		o.cfgvalue = function(section_id) {
			var name = uci.get('qmodem', section_id, 'name') || '';
			return name.toUpperCase();
		};

		o = s.option(form.DummyValue, 'alias', _('Modem Alias'));
		o.cfgvalue = function(section_id) {
			return uci.get('qmodem', section_id, 'alias') || '-';
		};

	o = s.option(form.DummyValue, 'state', _('Status'));
	o.cfgvalue = function(section_id) {
		var state = uci.get('qmodem', section_id, 'state');
		return state ? _(state.toUpperCase()) : _('Unknown');
	};

	// Dial Log View Button
	o = s.option(form.DummyValue, '_dial_log', _('Dial Log'));
	o.rawhtml = true;
	o.modalonly = false;
	o.editable = true;
	o.cfgvalue = L.bind(function(section_id) {
		var enable_dial = uci.get('qmodem', section_id, 'enable_dial');
		if (enable_dial === '0') {
			return E('span', {}, '-');
		}
		
		return E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, function(section_id) {
				this.showDialLogDialog(section_id);
			}, section_id)
		}, _('View Log'));
	}, this);

	// Dial Control Buttons
	o = s.option(form.DummyValue, '_dial_controls', _('Dial Control'));
		o.rawhtml = true;
		o.modalonly = false;
		o.editable = true;
		o.cfgvalue = function(section_id) {
			var enable_dial = uci.get('qmodem', section_id, 'enable_dial');
			if (enable_dial === '0') {
				return E('div', {}, _('Dial disabled for this modem'));
			}
			
			return E('div', { 
				'class': 'cbi-value-field', 
				'id': 'dial-controls-' + section_id,
				'data-section': section_id
			}, [
				E('span', {}, _('Loading...'))
			]);
		};

	// ============ Modal Configuration Options ============
	
	// General Settings
	o = s.option(form.Value, 'alias', _('Modem Alias'));
	o.rmempty = true;
	o.modalonly = true;

	o = s.option(form.DynamicList, 'dns_list', _('DNS'));
	o.placeholder = _('If the DNS server is not set, it will use the DNS server leased by the operator.');
	o.rmempty = true;
	o.modalonly = true;

	o = s.option(form.Flag, 'use_ubus', _('Use Ubus'));
	o.default = '0';
	o.rmempty = false;
	o.modalonly = true;

	// Advanced Settings
	o = s.option(form.Flag, 'force_set_apn', _('Force Set APN'));
	o.description = _('If enabled, the APN will be set even if it matches the current configuration.(only works with tom modified version of quectel-cm)');
	o.default = '0';
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Flag, 'en_bridge', _('Bridge Mode'));
	o.description = _('Caution: Only avalible for quectel sdx 5G Modem.');
	o.default = '0';
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Value, 'bridge_port', _('Bridge Port'));
	o.description = _('Device-level bridge port for passthrough. If set, it overrides the slot default bridge port.');
	o.rmempty = true;
	o.modalonly = true;
	if (this.networkInterfaces && this.networkInterfaces.length > 0) {
		this.networkInterfaces.forEach(function(iface) {
			o.value(iface.id, iface.label);
		});
	}

	o = s.option(form.Flag, 'do_not_add_dns', _('Do Not modify resolv.conf'));
	o.description = _('quectel-CM will append the DNS server to the resolv.conf file by default.if you do not want to modify the resolv.conf file, please check this option.');
	o.default = '0';
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Flag, 'donot_nat', _('Do Not NAT(Only for Quectel Modem)'));
	o.description = _('If enabled, will turn off NAT function on quectel modem.');
	o.default = '0';
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Flag, 'ra_master', _('RA Master'));
	o.description = _('Caution: Enabling this option will make it the IPV6 RA Master, and only one interface can be configured as such.');
	o.default = '0';
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Flag, 'extend_prefix', _('Extend Prefix'));
	o.description = _('Once checking, the prefix will be apply to lan zone');
	o.default = '0';
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Value, 'pdp_index', _('PDP Context Index'));
	o.rmempty = true;
	o.modalonly = true;

	o = s.option(form.ListValue, 'pdp_type', _('PDP Type'));
	o.value('ip', _('IPv4'));
	o.value('ipv6', _('IPv6'));
	o.value('ipv4v6', _('IPv4/IPv6'));
	o.value('ethernet', _('Ethernet'));
	o.default = 'ipv4v6';
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Value, 'apn', _('APN'));
	o.placeholder = _('Auto Choose');
	o.rmempty = true;
	o.modalonly = true;
	o.value('', _('Auto Choose'));
	o.value('cmnet', _('China Mobile (CN)'));
	o.value('3gnet', _('China Unicom (CN)'));
	o.value('ctnet', _('China Telecom (CN)'));
	o.value('cbnet', _('China Broadcast (CN)'));
	o.value('5gscuiot', _('Skytone (CN)'));
	// Switzerland (CH)
	o.value('gprs.swisscom.ch', _('Swisscom (CH)'));
	o.value('internet', 'Salt (CH), Sunrise (CH), O2 (DE), 1&1 (DE)');
	// Germany (DE)
	o.value('web.vodafone.de', _('Vodafone (DE)'));
	o.value('internet.telekom', _('Telekom (DE)'));
	o.value('internet.eplus.de', _('E-Plus (DE)'));
	// Austria (AT)
	o.value('A1.net', _('A1 (AT)'));
	o.value('drei.at', _('Drei (AT)'));
	o.value('internet.t-mobile.at', _('Magenta (AT)'));
	// Philippines (PH)
	o.value('http.globe.com.ph', _('Globe Prepaid (PH)'));
	o.value('internet.globe.com.ph', _('Globe Postpaid (PH)'));
	o.value('internet', _('Smart Communications (PH)'));
	o.value('internet.dito.ph', _('Dito Telecomunity (PH)'));
	// Malaysia (MY)
	o.value('celcom3g', _('Celcom (MY)'));
	o.value('diginet', _('DiGi (MY)'));
	o.value('unet', _('Maxis | Hotlink (MY)'));
	o.value('hos', _('Maxis UT (MY)'));
	o.value('yes4g', _('YES (MY)'));
	o.value('my3g', _('UMobile (MY)'));
	o.value('unifi', _('Unifi (MY)'));
	// Russia (RU)
	o.value('internet.beeline.ru', _('Beeline (RU)'));
	o.value('internet.mts.ru', _('MTS (RU)'));
	o.value('internet', _('Megafon (RU)'));
	o.value('internet.tele2.ru', _('Tele2 (RU)'));
	o.value('internet.yota', _('Yota (RU)'));
	o.value('m.tinkoff', _('T-mobile (RU)'));
	o.value('internet.rtk.ru', _('Rostelecom (RU)'));
	o.value('internet.sberbank-tele.com', _('Sber Mobile (RU)'));

	o = s.option(form.ListValue, 'auth', _('Authentication Type'));
	o.value('none', _('NONE'));
	o.value('MsChapV2', _('MsChapV2'));
	o.value('pap', 'PAP');
	o.value('chap', 'CHAP');
	o.default = 'none';
	o.rmempty = false;
	o.modalonly = true;

	o = s.option(form.Value, 'username', _('PAP/CHAP Username'));
	o.rmempty = true;
	o.modalonly = true;
	o.depends('auth', 'both');
	o.depends('auth', 'pap');
	o.depends('auth', 'chap');
	o.depends('auth', 'MsChapV2');

	o = s.option(form.Value, 'password', _('PAP/CHAP Password'));
	o.password = true;
	o.rmempty = true;
	o.modalonly = true;
	o.depends('auth', 'both');
	o.depends('auth', 'pap');
	o.depends('auth', 'chap');
	o.depends('auth', 'MsChapV2');

	o = s.option(form.Value, 'pincode', _('PIN Code'));
	o.description = _('If the PIN code is not set, leave it blank.');
	o.rmempty = true;
	o.modalonly = true;

	// Slot 2 Configuration
	o = s.option(form.Value, 'apn2', _('APN') + ' 2');
	o.description = _('If slot 2 config is not set,will use slot 1 config.');
	o.placeholder = _('Auto Choose');
	o.rmempty = true;
	o.modalonly = true;
	o.value('', _('Auto Choose'));
	o.value('cmnet', _('China Mobile (CN)'));
	o.value('3gnet', _('China Unicom (CN)'));
	o.value('ctnet', _('China Telecom (CN)'));
	o.value('cbnet', _('China Broadcast (CN)'));
	o.value('5gscuiot', _('Skytone (CN)'));
	// Switzerland (CH)
	o.value('gprs.swisscom.ch', _('Swisscom (CH)'));
	o.value('internet', 'Salt (CH), Sunrise (CH), O2 (DE), 1&1 (DE)');
	// Germany (DE)
	o.value('web.vodafone.de', _('Vodafone (DE)'));
	o.value('internet.telekom', _('Telekom (DE)'));
	o.value('internet.eplus.de', _('E-Plus (DE)'));
	// Austria (AT)
	o.value('A1.net', _('A1 (AT)'));
	o.value('drei.at', _('Drei (AT)'));
	o.value('internet.t-mobile.at', _('Magenta (AT)'));
	// Philippines (PH)
	o.value('http.globe.com.ph', _('Globe Prepaid (PH)'));
	o.value('internet.globe.com.ph', _('Globe Postpaid (PH)'));
	o.value('internet', _('Smart Communications (PH)'));
	o.value('internet.dito.ph', _('Dito Telecomunity (PH)'));
	// Malaysia (MY)
	o.value('celcom3g', _('Celcom (MY)'));
	o.value('diginet', _('DiGi (MY)'));
	o.value('unet', _('Maxis | Hotlink (MY)'));
	o.value('hos', _('Maxis UT (MY)'));
	o.value('yes4g', _('YES (MY)'));
	o.value('my3g', _('UMobile (MY)'));
	o.value('unifi', _('Unifi (MY)'));
	// Russia (RU)
	o.value('internet.beeline.ru', _('Beeline (RU)'));
	o.value('internet.mts.ru', _('MTS (RU)'));
	o.value('internet', _('Megafon (RU)'));
	o.value('internet.tele2.ru', _('Tele2 (RU)'));
	o.value('internet.yota', _('Yota (RU)'));
	o.value('m.tinkoff', _('T-mobile (RU)'));
	o.value('internet.rtk.ru', _('Rostelecom (RU)'));
	o.value('internet.sberbank-tele.com', _('Sber Mobile (RU)'));

	o = s.option(form.Value, 'metric', _('Metric'));
	o.description = _('The metric value is used to determine the priority of the route. The smaller the value, the higher the priority. Cannot duplicate.');
	o.default = '10';
	o.rmempty = true;
	o.modalonly = true;

	// Pre Dial Delay
	o = s.option(form.Value, 'pre_dial_delay', _('Pre Dial Delay') + ' ' + _('(beta)'));
	o.description = _('Delay of executing AT command before dialing, in seconds.') + _('(still in beta)');
	o.placeholder = _('Enter delay in seconds');
	o.default = '0';
	o.datatype = 'uinteger';
	o.rmempty = true;
	o.modalonly = true;

	// Post Init Delay
	o = s.option(form.Value, 'post_init_delay', _('Post Init Delay') + ' ' + _('(beta)'));
	o.description = _('Delay of executing AT command after modem initialization, in seconds.') + _('(still in beta)');
	o.placeholder = _('Enter delay in seconds');
	o.default = '0';
	o.datatype = 'uinteger';
	o.rmempty = true;
	o.modalonly = true;

	// Post Init AT Commands
	o = s.option(form.DynamicList, 'post_init_at_cmds', _('Post Init AT Commands') + ' ' + _('(beta)'));
	o.description = _('AT commands to execute after modem initialization.') + _('(still in beta)');
	o.placeholder = _('Enter AT commands');
	o.rmempty = true;
	o.modalonly = true;

	// Pre Dial AT Commands
	o = s.option(form.DynamicList, 'pre_dial_at_cmds', _('Pre Dial AT Commands') + ' ' + _('(beta)'));
	o.description = _('AT commands to execute before dialing.') + _('(still in beta)');
	o.placeholder = _('Enter AT commands');
	o.rmempty = true;
	o.modalonly = true;

	return m.render().then(L.bind(function(rendered) {
			// Update dial controls for all modems
			this.updateAllDialControls();
			// Update connection status indicators
			this.updateAllStatusIndicators();
			// Start polling for dial status
			this.startDialStatusPolling();
			// Start polling for connection status
			this.startStatusIndicatorPolling();
			// Start polling for RC status
			this.startRcStatusPolling();
			return rendered;
		}, this));
	},

	updateDialControls: function(section_id, isRunning) {
		var container = document.getElementById('dial-controls-' + section_id);
		if (!container) return;

		// Clear existing content
		while (container.firstChild) {
			container.removeChild(container.firstChild);
		}

		var buttons = [];
		
		if (isRunning) {
			// Show Hang and ReDial buttons when service is running
			buttons.push(
				E('button', {
					'class': 'cbi-button cbi-button-reset',
					'click': ui.createHandlerFn(this, function(section_id) {
						return qmodem.modemHang(section_id).then(L.bind(function(result) {
							if (result && result.result && result.result.status === '1') {
								ui.addNotification(null, E('p', _('Hang command sent successfully')));
								// Update status after hang
								setTimeout(L.bind(function() {
									this.updateDialControlsForSection(section_id);
								}, this), 1000);
							} else {
								ui.addNotification(null, E('p', _('Failed to send hang command')), 'error');
							}
						}, this)).catch(function(err) {
							ui.addNotification(null, E('p', _('Error: ') + err.message), 'error');
						});
					}, section_id)
				}, _('Hang')),
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, function(section_id) {
						return qmodem.modemRedial(section_id).then(function(result) {
							if (result && result.result && result.result.status === '1') {
								ui.addNotification(null, E('p', _('Redial command sent successfully')));
							} else {
								ui.addNotification(null, E('p', _('Failed to send redial command')), 'error');
							}
						}).catch(function(err) {
							ui.addNotification(null, E('p', _('Error: ') + err.message), 'error');
						});
					}, section_id)
				}, _('ReDial'))
			);
		} else {
			// Show Dial button when service is not running
			buttons.push(
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function(section_id) {
						return qmodem.modemDial(section_id).then(L.bind(function(result) {
							if (result && result.result && result.result.status === '1') {
								ui.addNotification(null, E('p', _('Dial command sent successfully')));
								// Update status after dial
								setTimeout(L.bind(function() {
									this.updateDialControlsForSection(section_id);
								}, this), 1000);
							} else {
								ui.addNotification(null, E('p', _('Failed to send dial command')), 'error');
							}
						}, this)).catch(function(err) {
							ui.addNotification(null, E('p', _('Error: ') + err.message), 'error');
						});
					}, section_id)
				}, _('Dial'))
			);
		}

		buttons.forEach(function(btn) {
			container.appendChild(btn);
		});
	},

	updateDialControlsForSection: function(section_id) {
		return qmodem.getDialStatus(section_id).then(L.bind(function(result) {
			if (result && result.running !== undefined) {
				var isRunning = (result.running === 'true' || result.running === true);
				this.updateDialControls(section_id, isRunning);
			}
		}, this)).catch(function(err) {
			console.error('Failed to get dial status for ' + section_id + ':', err);
		});
	},

	updateAllDialControls: function() {
		var sections = uci.sections('qmodem', 'modem-device');
		sections.forEach(L.bind(function(section) {
			var enable_dial = uci.get('qmodem', section['.name'], 'enable_dial');
			if (enable_dial !== '0') {
				this.updateDialControlsForSection(section['.name']);
			}
		}, this));
	},

	startDialStatusPolling: function() {
		poll.add(L.bind(function() {
			this.updateAllDialControls();
		}, this), 5);
	},

	updateStatusIndicator: function(section_id) {
		var container = document.getElementById('status-indicator-' + section_id);
		if (!container) return;

		return qmodem.getConnectStatus(section_id).then(L.bind(function(result) {
			// Update cached data
			if (!this.connectionStatusData) {
				this.connectionStatusData = {};
			}
			this.connectionStatusData[section_id] = result;
			
			var color = '#FFA500'; // Yellow (default for error/unknown)
			var title = _('Unknown');

			if (result && result.connection_status !== undefined) {
				var status = result.connection_status;
				status = status.toString().toLowerCase();
				if (status === 'yes' || status === 'connected' || status === '1' || status === 'true' || status === true) {
					color = '#00FF00'; // Green (connected)
					title = _('Connected');
				} else if (status === 'no' || status === 'disconnected' || status === '0' || status === 'false' || status === false) {
					color = '#FF0000'; // Red (disconnected)
					title = _('Disconnected');
				}
			}

			// Update the dot color
			while (container.firstChild) {
				container.removeChild(container.firstChild);
			}
			container.appendChild(
				E('span', {
					'style': 'display: inline-block; width: 12px; height: 12px; border-radius: 50%; background-color: ' + color + ';',
					'title': title
				})
			);
		}, this)).catch(function(err) {
			// On error, show yellow dot
			while (container.firstChild) {
				container.removeChild(container.firstChild);
			}
			container.appendChild(
				E('span', {
					'style': 'display: inline-block; width: 12px; height: 12px; border-radius: 50%; background-color: #FFA500;',
					'title': _('Error: ') + err.message
				})
			);
		});
	},

	updateAllStatusIndicators: function() {
		var sections = uci.sections('qmodem', 'modem-device');
		sections.forEach(L.bind(function(section) {
			this.updateStatusIndicator(section['.name']);
		}, this));
	},

	startStatusIndicatorPolling: function() {
		poll.add(L.bind(function() {
			this.updateAllStatusIndicators();
		}, this), 5);
	},

	startRcStatusPolling: function() {
		poll.add(L.bind(function() {
			this.updateRcStatus();
		}, this), 10);
	},

	updateRcStatus: function() {
		var statusContainer = document.getElementById('rc-status-container');
		var controlContainer = document.getElementById('rc-control-container');

		if (!statusContainer || !controlContainer) {
			return Promise.resolve();
		}

		return qmodem.rcStatus('qmodem_network').then(L.bind(function(result) {
			this.rcStatusData = result;
			var status = result && result.qmodem_network ? result.qmodem_network : null;

			// Update status display
			while (statusContainer.firstChild) {
				statusContainer.removeChild(statusContainer.firstChild);
			}

			if (status) {
				var enabled = status.enabled === true || status.enabled === 'true';
				var running = status.running === true || status.running === 'true';

				statusContainer.appendChild(E('div', {}, [
					E('span', {}, _('Enabled') + ': ' + (enabled ? _('Yes') : _('No'))),
					E('span', { 'style': 'margin-left: 12px;' }, _('Running') + ': ' + (running ? _('Yes') : _('No')))
				]));

				// Update control buttons
				while (controlContainer.firstChild) {
					controlContainer.removeChild(controlContainer.firstChild);
				}

				var buttons = [];

				// Running control: show Start if not running, show Stop and Restart if running
				if (!running) {
					buttons.push(
						E('button', {
							'class': 'cbi-button cbi-button-action',
							'id': 'rc-start-button',
							'click': ui.createHandlerFn(this, function() {
								var self = this;
								return callInitAction('qmodem_network', 'start')
									.then(function() {
										ui.addNotification(null, E('p', _('QModem Network started successfully')));
										return self.updateRcStatus();
									})
									.catch(function(err) {
										ui.addNotification(null, E('p', _('Failed to start QModem Network: ') + err.message), 'error');
										return self.updateRcStatus();
									});
							})
						}, _('Start'))
					);
				} else {
					buttons.push(
						E('button', {
							'class': 'cbi-button cbi-button-reset',
							'id': 'rc-stop-button',
							'click': ui.createHandlerFn(this, function() {
								var self = this;
								return callInitAction('qmodem_network', 'stop')
									.then(function() {
										ui.addNotification(null, E('p', _('QModem Network stopped successfully')));
										return self.updateRcStatus();
									})
									.catch(function(err) {
										ui.addNotification(null, E('p', _('Failed to stop QModem Network: ') + err.message), 'error');
										return self.updateRcStatus();
									});
							})
						}, _('Stop'))
					);
					buttons.push(
						E('button', {
							'class': 'cbi-button cbi-button-apply',
							'id': 'rc-restart-button',
							'click': ui.createHandlerFn(this, function() {
								var self = this;
								return callInitAction('qmodem_network', 'restart')
									.then(function() {
										ui.addNotification(null, E('p', _('QModem Network restarted successfully')));
										return self.updateRcStatus();
									})
									.catch(function(err) {
										ui.addNotification(null, E('p', _('Failed to restart QModem Network: ') + err.message), 'error');
										return self.updateRcStatus();
									});
							})
						}, _('Restart'))
					);
				}

				buttons.push(E('span', { 'style': 'margin: 0 8px;' }, ' | '));

				// Enabled control: show Enable if not enabled, show Disable if enabled
				if (!enabled) {
					buttons.push(
						E('button', {
							'class': 'cbi-button cbi-button-apply',
							'id': 'rc-enable-button',
							'click': ui.createHandlerFn(this, function() {
								var self = this;
								return callInitAction('qmodem_network', 'enable')
									.then(function() {
										ui.addNotification(null, E('p', _('QModem Network enabled successfully')));
										return self.updateRcStatus();
									})
									.catch(function(err) {
										ui.addNotification(null, E('p', _('Failed to enable QModem Network: ') + err.message), 'error');
										return self.updateRcStatus();
									});
							})
						}, _('Enable'))
					);
				} else {
					buttons.push(
						E('button', {
							'class': 'cbi-button cbi-button-negative',
							'id': 'rc-disable-button',
							'click': ui.createHandlerFn(this, function() {
								var self = this;
								return callInitAction('qmodem_network', 'disable')
									.then(function() {
										ui.addNotification(null, E('p', _('QModem Network disabled successfully')));
										return self.updateRcStatus();
									})
									.catch(function(err) {
										ui.addNotification(null, E('p', _('Failed to disable QModem Network: ') + err.message), 'error');
										return self.updateRcStatus();
									});
							})
						}, _('Disable'))
					);
				}

				buttons.forEach(function(btn) {
					controlContainer.appendChild(btn);
				});
			} else {
				statusContainer.appendChild(E('span', {}, _('Failed to load status')));
			}
		}, this)).catch(L.bind(function(err) {
			while (statusContainer.firstChild) {
				statusContainer.removeChild(statusContainer.firstChild);
			}
			statusContainer.appendChild(E('span', {}, _('Error: ') + err.message));
		}, this));
	},

	showDialLogDialog: function(section_id) {
		var name = uci.get('qmodem', section_id, 'name');
		var alias = uci.get('qmodem', section_id, 'alias');
		var title = (alias || name || section_id) + ' - ' + _('Dial Log');
		
		var logContent = E('div', { 'style': 'min-height: 300px;' }, [
			E('div', { 'style': 'text-align: center; padding: 20px;' }, [
				E('span', { 'class': 'spinning' }, _('Loading...'))
			])
		]);

		var dialog = ui.showModal(title, [
			E('style', {}, '\
				.dial-log-content { \
					padding: 10px; \
					border-radius: 3px; \
					max-height: 400px; \
					width: 100%; \
					overflow-y: auto; \
					font-family: monospace; \
					font-size: 12px; \
					white-space: pre-wrap; \
					word-wrap: break-word; \
				} \
				.dial-log-empty { \
					text-align: center; \
					padding: 40px; \
				}'),
			logContent,
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': L.bind(function() {
						this.downloadDialLog(section_id);
					}, this)
				}, _('Download')),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-reset',
					'click': L.bind(function() {
						this.clearDialLogDialog(section_id, logContent);
					}, this)
				}, _('Clear')),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'click': ui.hideModal
				}, _('Close'))
			])
		], 'cbi-modal');

		// Load log content
		this.loadDialLog(section_id, logContent);
	},

	loadDialLog: function(section_id, container) {
		return qmodem.getDialLog(section_id).then(function(result) {
			while (container.firstChild) {
				container.removeChild(container.firstChild);
			}

			if (result && result.log) {
				if (result.log.trim() === '') {
					container.appendChild(
						E('div', { 'class': 'dial-log-empty' }, _('No log available'))
					);
				} else {
					container.appendChild(
							E('textarea', { 'class': 'dial-log-content','readonly':'readonly','rows':'20','maxlength':'160' }, result.log)
					);
				}
			} else {
				container.appendChild(
					E('div', { 'class': 'dial-log-empty' }, _('Failed to load log'))
				);
			}
		}).catch(function(err) {
			while (container.firstChild) {
				container.removeChild(container.firstChild);
			}
			container.appendChild(
				E('div', { 'class': 'dial-log-empty' }, _('Error: ') + err.message)
			);
		});
	},

	downloadDialLog: function(section_id) {
		return qmodem.getDialLog(section_id).then(function(result) {
			if (result && result.log) {
				var name = uci.get('qmodem', section_id, 'name') || section_id;
				var alias = uci.get('qmodem', section_id, 'alias') || '';
				var filename = 'dial_log_' + (alias || name) + '_' + 
					new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5) + '.txt';
				
				var blob = new Blob([result.log], { type: 'text/plain' });
				var url = window.URL.createObjectURL(blob);
				var a = document.createElement('a');
				a.href = url;
				a.download = filename;
				document.body.appendChild(a);
				a.click();
				window.URL.revokeObjectURL(url);
				document.body.removeChild(a);
				
				ui.addNotification(null, E('p', _('Log downloaded successfully')));
			} else {
				ui.addNotification(null, E('p', _('No log content to download')), 'warning');
			}
		}).catch(function(err) {
			ui.addNotification(null, E('p', _('Failed to download log: ') + err.message), 'error');
		});
	},

	clearDialLogDialog: function(section_id, container) {
		ui.showModal(_('Clear Dial Log'), [
			E('p', {}, _('Are you sure you want to clear the dial log?')),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'click': ui.hideModal
				}, _('Cancel')),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'click': L.bind(function() {
						qmodem.clearDialLog(section_id).then(L.bind(function(result) {
							if (result && result.result && result.result.status === '1') {
								ui.addNotification(null, E('p', _('Log cleared successfully')));
								ui.hideModal();
								// Reload the main dialog
								setTimeout(L.bind(function() {
									this.showDialLogDialog(section_id);
								}, this), 300);
							} else {
								ui.addNotification(null, E('p', _('Failed to clear log')), 'error');
								ui.hideModal();
							}
						}, this)).catch(function(err) {
							ui.addNotification(null, E('p', _('Error: ') + err.message), 'error');
							ui.hideModal();
						});
					}, this)
				}, _('Confirm'))
			])
		]);
	}
});
