'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require poll';
'require qmodem.modem_cfg as modemCfg';

var callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board'
});

var callScanPcie = rpc.declare({
	object: 'qmodem',
	method: 'scan_pcie'
});

var callScanUsb = rpc.declare({
	object: 'qmodem',
	method: 'scan_usb'
});

var callScanAll = rpc.declare({
	object: 'qmodem',
	method: 'scan_all'
});

var callGetPcieDevices = rpc.declare({
	object: 'qmodem',
	method: 'get_pcie_devices'
});

var callGetUsbDevices = rpc.declare({
	object: 'qmodem',
	method: 'get_usb_devices'
});

var callGetLeds = rpc.declare({
	object: 'qmodem',
	method: 'get_leds'
});

var callGetNetworkInterfaces = rpc.declare({
	object: 'qmodem',
	method: 'get_network_interfaces'
});

var callGetTtyPorts = rpc.declare({
	object: 'qmodem',
	method: 'get_tty_ports'
});

var callGetAvailableDevices = rpc.declare({
	object: 'qmodem',
	method: 'get_available_devices'
});

var callRemoveModem = rpc.declare({
	object: 'qmodem',
	method: 'remove_modem',
	params: ['config_section'],
	expect: { }
});

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('qmodem'),
			callSystemBoard(),
			callGetPcieDevices(),
			callGetUsbDevices(),
			callGetLeds(),
			callGetNetworkInterfaces(),
			callGetTtyPorts(),
			callGetAvailableDevices()
		]).then(L.bind(function(results) {
			this.pcieDevices = results[2] && results[2].devices ? results[2].devices : [];
			this.usbDevices = results[3] && results[3].devices ? results[3].devices : [];
			this.leds = results[4] && results[4].leds ? results[4].leds : [];
			this.networkInterfaces = results[5] && results[5].interfaces ? results[5].interfaces : [];
			this.ttyPorts = results[6] && results[6].ports ? results[6].ports : [];
			this.availableDevices = results[7] && results[7].devices ? results[7].devices : {};
			return results;
		}, this));
	},

	render: function(data) {
		var m, s, o;

		m = new form.Map('qmodem', _('QModem Settings'));

		// ===========================================
		// Modem Probe Settings
		// ===========================================
		s = m.section(form.NamedSection, 'main', 'main', _('Modem Probe Settings'));

		o = s.option(form.Flag, 'at_tool', _('Alternative AT Tools'));
		o.description = _('If enabled, using alternative AT Tools');
		o.default = '0';

		o = s.option(form.Value, 'start_delay', _('Delay Start'));
		o.description = _('Units: seconds');
		o.datatype = 'and(uinteger,min(0),max(99))';
		o.default = '0';
		o.placeholder = '0';

		o = s.option(form.Flag, 'block_auto_probe', _('Block Auto Probe/Remove'));
		o.description = _('If enabled, the modem auto scan will be blocked.');
		o.default = '0';

		o = s.option(form.Flag, 'enable_pcie_scan', _('Enable PCIe Scan'));
		o.description = _('Once enabled, the PCIe ports will be scanned on every boot.');
		o.default = '0';

		o = s.option(form.Flag, 'enable_usb_scan', _('Enable USB Scan'));
		o.description = _('Once enabled, the USB ports will be scanned on every boot.');
		o.default = '1';

		o = s.option(form.ListValue, 'scan_log_level', _('Scan Log Level'));
		o.value('debug', _('Debug'));
		o.value('info', _('Info'));
		o.value('notice', _('Notice'));
		o.value('warn', _('Warning'));
		o.value('err', _('Error'));
		o.default = 'info';

		o = s.option(form.Value, 'scan_workers', _('Scan Workers'));
		o.datatype = 'and(uinteger,min(1),max(16))';
		o.default = '4';

		o = s.option(form.Value, 'at_probe_workers', _('AT Probe Workers'));
		o.datatype = 'and(uinteger,min(1),max(16))';
		o.default = '4';

		o = s.option(form.Value, 'at_timeout_fast', _('Fast AT Timeout'));
		o.description = _('Units: seconds');
		o.datatype = 'and(uinteger,min(1),max(30))';
		o.default = '2';

		o = s.option(form.Value, 'at_timeout_model', _('Model AT Timeout'));
		o.description = _('Units: seconds');
		o.datatype = 'and(uinteger,min(1),max(60))';
		o.default = '8';

		o = s.option(form.Value, 'hotplug_add_delay', _('Hotplug Add Delay'));
		o.description = _('Units: seconds');
		o.datatype = 'and(uinteger,min(0),max(60))';
		o.default = '8';

		o = s.option(form.Value, 'add_retry_delay', _('Add Retry Delay'));
		o.description = _('Units: seconds');
		o.datatype = 'and(uinteger,min(0),max(60))';
		o.default = '8';

		o = s.option(form.Value, 'add_retry_max', _('Add Retry Max'));
		o.datatype = 'and(uinteger,min(0),max(20))';
		o.default = '5';

		o = s.option(form.Flag, 'try_preset_usb', _('Try Preset USB Port'));
		o.description = _('Attempt to use pre-configured USB settings from the CPE vendor.');
		o.default = '0';

		o = s.option(form.Flag, 'try_preset_pcie', _('Try Preset PCIe Port'));
		o.description = _('Attempt to use pre-configured PCIe settings from the CPE vendor.');
		o.default = '0';

		// Manual Scan Buttons
		o = s.option(form.Button, '_scan_pcie', _('Scan PCIe Manually'));
		o.inputstyle = 'apply';
		o.onclick = L.bind(function() {
			ui.showModal(_('Scanning'), [
				E('p', { 'class': 'spinning' }, _('Scanning PCIe ports, please wait...'))
			]);
			return callScanPcie()
				.then(function(res) {
					ui.hideModal();
					if (res.code === 0) {
						ui.addNotification(null, E('p', res.message || _('PCIe scan completed successfully')), 'info');
					} else {
						var msg = res.message || _('PCIe scan failed');
						if (res.output) msg += ' - ' + res.output;
						ui.addNotification(null, E('p', msg), 'warning');
						window.location.reload();
					}
				})
				.catch(function(err) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('PCIe scan error: ') + (err.message || err)), 'error');
				});
		}, this);

		o = s.option(form.Button, '_scan_usb', _('Scan USB Manually'));
		o.inputstyle = 'apply';
		o.onclick = L.bind(function() {
			ui.showModal(_('Scanning'), [
				E('p', { 'class': 'spinning' }, _('Scanning USB ports, please wait...'))
			]);
			return callScanUsb()
				.then(function(res) {
					ui.hideModal();
					if (res.code === 0) {
						ui.addNotification(null, E('p', res.message || _('USB scan completed successfully')), 'info');
						window.location.reload();
					} else {
						var msg = res.message || _('USB scan failed');
						if (res.output) msg += ' - ' + res.output;
						ui.addNotification(null, E('p', msg), 'warning');
					}
				})
				.catch(function(err) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('USB scan error: ') + (err.message || err)), 'error');
				});
		}, this);

		o = s.option(form.Button, '_scan_all', _('Scan ALL Manually'));
		o.inputstyle = 'apply';
		o.onclick = L.bind(function() {
			ui.showModal(_('Scanning'), [
				E('p', { 'class': 'spinning' }, _('Scanning all ports, please wait...'))
			]);
			return callScanAll()
				.then(function(res) {
					ui.hideModal();
					if (res.code === 0) {
						ui.addNotification(null, E('p', res.message || _('Full scan completed successfully')), 'info');
						window.location.reload();
					} else {
						var msg = res.message || _('Full scan failed');
						if (res.output) msg += ' - ' + res.output;
						ui.addNotification(null, E('p', msg), 'warning');
					}
				})
				.catch(function(err) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('Full scan error: ') + (err.message || err)), 'error');
				});
		}, this);



		// Modem Configuration (Device Settings Only)
		s = m.section(form.GridSection, 'modem-device', _('Modem Devices'));
		s.anonymous = true;
		s.sortable = true;
		s.modaltitle = L.bind(function(section_id) {
			var name = uci.get('qmodem', section_id, 'name');
			return _('Modem Device') + ': ' + (name || section_id);
		}, this);

		// Use available devices from RPC call
		var availableDevices = this.availableDevices || {};

		// Custom add handler
		s.addremove = true;
		s.handleAdd = function(ev, section_id) {
			var deviceKeys = Object.keys(availableDevices);
			if (deviceKeys.length === 0) {
				ui.addNotification(null, E('p', _('No devices available. Please scan for devices first.')), 'warning');
				return;
			}

			var selectList = deviceKeys.map(function(key) {
				return E('option', { value: key }, availableDevices[key].label);
			});

			ui.showModal(_('Add Modem Device'), [
				E('p', _('Select a device to configure:')),
				E('div', { 'class': 'cbi-section' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Available Devices')),
					E('select', { 'id': 'device-select', 'class': 'cbi-input-select' }, selectList)
				]),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn cbi-button-neutral',
						'click': ui.hideModal
					}, _('Cancel')),
					E('button', {
						'class': 'btn cbi-button-positive',
						'click': L.bind(function() {
							var select = document.getElementById('device-select');
							var selectedKey = select.value;
							var deviceInfo = availableDevices[selectedKey];
							
							// Create new section with selected device name
							var sid = uci.add('qmodem', 'modem-device', selectedKey);
							
							// Set type and path automatically
							uci.set('qmodem', sid, 'data_interface', deviceInfo.type);
							uci.set('qmodem', sid, 'path', deviceInfo.path);
							
							ui.hideModal();
							m.save().then(function() {
								window.location.reload();
							});
						}, this)
					}, _('Add'))
				])
			]);
		};
		//call remove_modem rpc method on remove
		s.handleRemove = function(section_id, isturst) {
			//add a comfirmation dialog
			if (!confirm(_('Are you sure you want to remove this modem device? this cannot be roll back with uci machanism.'))) {
				return;
			}
			return callRemoveModem(section_id)
				.then(function() {
					ui.addNotification(null, E('p', _('Modem device removed successfully')), 'info');
					//refresh the page
					window.location.reload();
				})
				.catch(function(err) {
					ui.addNotification(null, E('p', _('Modem device removal failed: ') + (err.message || err)), 'error');
				});
		};


		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.editable = true;
		o.modalonly = true;

		o = s.option(form.DummyValue, 'data_interface', _('Type'));
		o.editable = true;
		o.cfgvalue = function(section_id) {
			var type = uci.get('qmodem', section_id, 'data_interface') || '-';
			return type.toUpperCase();
		};

		o = s.option(form.Flag, 'soft_reboot', _('Soft Reboot'));
		o.description = _('enable modem soft reboot');
		o.default = '0';
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'name', _('Model Name'));
		o.placeholder = _('e.g.') + ' RG500Q';
		o.rmempty = false;	o = s.option(form.Value, 'alias', _('Alias'));
	o.placeholder = _('e.g.') + ' Modem1';
	o.editable = true;

	o = s.option(form.Value, 'path', _('Device Path'));
	o.placeholder = _('e.g.') + ' /sys/bus/usb/devices/1-1';
	o.rmempty = false;
	o.readonly = true;	o = s.option(form.Value, 'at_port', _('AT Port'));
	o.placeholder = _('e.g.') + ' /dev/ttyUSB2';
	o.rmempty = false;
	if (this.ttyPorts && this.ttyPorts.length > 0) {
		this.ttyPorts.forEach(function(port) {
			o.value(port.id, port.label);
		});
	}	o = s.option(form.Value, 'sms_at_port', _('SMS AT Port'));
	o.placeholder = _('e.g.') + ' /dev/ttyUSB2';
	if (this.ttyPorts && this.ttyPorts.length > 0) {
		this.ttyPorts.forEach(function(port) {
			o.value(port.id, port.label);
		});
	} 		o = s.option(form.Value, 'override_at_port', _('Override AT Port'));
	o.placeholder = _('e.g.') + ' /dev/ttyUSB3';
	if (this.ttyPorts && this.ttyPorts.length > 0) {
		this.ttyPorts.forEach(function(port) {
			o.value(port.id, port.label);
		});
	}		o = s.option(form.Flag, 'use_ubus', _('Use Ubus AT Daemon'));
		o.default = '0';


		// Additional modem configuration (modal only)
		//vendor
		o = s.option(form.ListValue, 'vendor', _('Vendor'));
		o.modalonly = true;
		o.optional = true;
		for (var key in modemCfg.manufacturers) {
			o.value(key, modemCfg.manufacturers[key]);
		}

		o = s.option(form.ListValue, 'platform', _('Platform'));
		o.modalonly = true;
		o.optional = true;
		for (var key in modemCfg.platforms) {
			o.value(key, modemCfg.platforms[key]);
		}

		o = s.option(form.DynamicList, 'modes', _('Supported Modes'));
		o.description = _('Supported driver modes (e.g., RNDIS/NCM/QMI/MBIM/ETH/PPP)');
		o.modalonly = true;
		o.optional = true;
		for (var key in modemCfg.modes) {
			o.value(key, modemCfg.modes[key]);
		}

		o = s.option(form.DynamicList, 'disabled_features', _('Disabled Features'));
		o.description = _('Select features to disable for this modem.');
		o.modalonly = true;
		o.optional = true;
		for (var key in modemCfg.disabled_features) {
			o.value(key, modemCfg.disabled_features[key]);
		}

		o = s.option(form.Value, 'wcdma_band', _('WCDMA Band'));
		o.placeholder = _('e.g.') + ' 1/2/5/8';
		o.modalonly = true;
		o.optional = true;

		o = s.option(form.Value, 'lte_band', _('LTE Band'));
		o.placeholder = _('e.g.') + ' 1/3/5/7/8/20';
		o.modalonly = true;
		o.optional = true;

		o = s.option(form.Value, 'nsa_band', _('NSA Band'));
		o.placeholder = _('e.g.') + ' 41/78';
		o.modalonly = true;
		o.optional = true;

		o = s.option(form.Value, 'sa_band', _('SA Band'));
		o.placeholder = _('e.g.') + ' 78/79';
		o.modalonly = true;
		o.optional = true;

	// ===========================================
	// Modem Slot Configuration
	// ===========================================
	s = m.section(form.GridSection, 'modem-slot', _('Modem Slot Configuration'));
	s.description = _('Configure physical slots for modem installation');
	s.anonymous = false;
	s.addremove = true;
	s.sortable = true;
	s.modaltitle = L.bind(function(section_id) {
		var slotId = uci.get('qmodem', section_id, 'slot');
		var alias = uci.get('qmodem', section_id, 'alias');
		return _('Modem Slot') + ': ' + (alias || slotId || section_id);
	}, this);

	o = s.option(form.ListValue, 'type', _('Slot Type'));
	o.value('usb', _('USB'));
	o.value('pcie', _('PCIe'));
	o.default = 'usb';
	o.editable = true;

	o = s.option(form.Value, 'slot', _('Slot ID'));
	o.description = _('Physical slot identifier (e.g., 1-1.4 for USB, 0000:01:00.0 for PCIe)');
	o.rmempty = false;
	o.editable = true;
	// Add PCIe devices
	if (this.pcieDevices && this.pcieDevices.length > 0) {
		this.pcieDevices.forEach(function(device) {
			o.value(device.id, device.label);
		});
	}
	// Add USB devices
	if (this.usbDevices && this.usbDevices.length > 0) {
		this.usbDevices.forEach(function(device) {
			o.value(device.id, device.label);
		});
	}

	o = s.option(form.Value, 'alias', _('Default Alias'));
	o.description = _('After setting this option, the first module loaded into this slot will automatically be assigned this default alias.');
	o.placeholder = _('e.g.') + ' Modem';
	o.editable = true;

	o = s.option(form.Value, 'default_metric', _('Default Metric'));
	o.description = _('The first module loaded into this slot will automatically be assigned this default metric.');
	o.datatype = 'range(1,255)';
	o.placeholder = _('e.g.') + ' 10';
	o.editable = true;

	o = s.option(form.Value, 'sim_led', _('SIM LED'));
	o.description = _('LED indicator for SIM card status');
	o.optional = true;
	o.modalonly = true;
	if (this.leds && this.leds.length > 0) {
		this.leds.forEach(function(led) {
			o.value(led.id, led.label);
		});
	}

	o = s.option(form.Value, 'net_led', _('Network LED'));
	o.description = _('LED indicator for network connection status');
	o.optional = true;
	o.modalonly = true;
	if (this.leds && this.leds.length > 0) {
		this.leds.forEach(function(led) {
			o.value(led.id, led.label);
		});
	}

	o = s.option(form.Value, 'ethernet_5g', _('5G Ethernet Interface'));
	o.description = _('For 5G modules using the Ethernet PHY connection, please specify the network interface name (e.g., eth0, eth1)');
	o.optional = true;
	o.modalonly = true;
	if (this.networkInterfaces && this.networkInterfaces.length > 0) {
		this.networkInterfaces.forEach(function(iface) {
			o.value(iface.id, iface.label);
		});
	}

	o = s.option(form.Value, 'bridge_port', _('Bridge Port'));
	o.description = _('Default bridge port for passthrough. Device-level bridge_port overrides this slot default.');
	o.optional = true;
	o.modalonly = true;
	if (this.networkInterfaces && this.networkInterfaces.length > 0) {
		this.networkInterfaces.forEach(function(iface) {
			o.value(iface.id, iface.label);
		});
	}

	o = s.option(form.Value, 'associated_usb', _('Associated USB'));
	o.description = _('For M.2 slots with both PCIe and USB support, specify the associated USB port (for ttyUSB access)');
	o.depends('type', 'pcie');
	o.optional = true;
	o.modalonly = true;
	if (this.usbDevices && this.usbDevices.length > 0) {
		this.usbDevices.forEach(function(device) {
			o.value(device.id, device.id);
		});
	}

	o = s.option(form.Value, 'gpio', _('Power GPIO'));
	o.description = _('GPIO pin for power control');
	o.optional = true;
	o.modalonly = true;

	o = s.option(form.Value, 'gpio_down', _('GPIO Value(Modem Power Down)'));
	o.depends({gpio: /./ } );
	o.placeholder = _('e.g.') + ' 0';
	o.modalonly = true;

	o = s.option(form.Value, 'gpio_up', _('GPIO Value(Modem Power Up)'));
	o.depends({gpio: /./ } );
	o.placeholder = _('e.g.') + ' 1';
	o.modalonly = true;

		return m.render();
	}
});
