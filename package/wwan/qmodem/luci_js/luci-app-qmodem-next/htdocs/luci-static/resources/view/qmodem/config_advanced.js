'use strict';
'require view';
'require ui';
'require dom';
'require qmodem.qmodem as qmodem';

return view.extend({
	load: function() {
		return qmodem.getModemSections();
	},

	render: function(modems) {
		if (!modems || modems.length === 0) {
			return E('div', { 'class': 'alert-message warning' }, 
				_('No modem configured.'));
		}

		var container = E('div', { 'class': 'cbi-map' });
		var title = E('h2', { 'class': 'cbi-map-caption' }, _('Advanced Configuration'));
		container.appendChild(title);

		// Create modem selector section
		var selectorSection = E('fieldset', { 'class': 'cbi-section' });
		var selectorTable = E('table', { 'class': 'table' });
		var selectorBody = E('tbody', {});
		var selectorRow = E('tr', { 'class': 'tr' });
		var labelCell = E('td', { 'class': 'td left', 'width': '33%' }, _('Modem Name'));
		var selectCell = E('td', { 'class': 'td' });
		
		// Create select dropdown
		var select = E('select', {
			'class': 'cbi-input-select',
			'id': 'modem_selector'
		});
		
		modems.forEach(function(modem) {
			if (modem.enabled) {
				select.appendChild(E('option', { 'value': modem.id }, modem.name));
			}
		});
		
		selectCell.appendChild(select);
		selectorRow.appendChild(labelCell);
		selectorRow.appendChild(selectCell);
		selectorBody.appendChild(selectorRow);
		selectorTable.appendChild(selectorBody);
		selectorSection.appendChild(selectorTable);
		container.appendChild(selectorSection);

		// Create tab container
		var tabContainer = E('div', { 'id': 'tab_container' });
		container.appendChild(tabContainer);

		var self = this;
		
		// Update function to show selected modem's tabs
		var updateTabs = function() {
			var selectedId = select.value;
			var selectedModem = modems.find(function(m) { return m.id === selectedId; });
			
			if (selectedModem) {
				dom.content(tabContainer, null);
				dom.append(tabContainer, E('div', { 'class': 'spinning' }, _('Loading...')));
				
				// Get disabled features for the modem
				qmodem.getDisabledFeatures(selectedModem.id).then(function(result) {
					var disabledFeatures = result.disabled_features || [];
					dom.content(tabContainer, self.createTabInterface(selectedModem, disabledFeatures));
				}).catch(function(e) {
					dom.content(tabContainer, E('div', { 'class': 'alert-message warning' }, 
						_('Error loading features: %s').format(e.message)));
				});
			}
		};

		// Selector change handler
		select.addEventListener('change', updateTabs);

		// Initial display
		updateTabs();

		return container;
	},

	createTabInterface: function(modem, disabledFeatures) {
		var self = this;
		var container = E('div', {});
		
		// Define all available features
		var features = {
			'DialMode': {
				name: _('Dial Mode'),
				handler: function() { return self.createDialModeTab(modem); }
			},
			'RatPrefer': {
				name: _('Network Preference'),
				handler: function() { return self.createRatPreferTab(modem); }
			},
			'IMEI': {
				name: _('Set IMEI'),
				handler: function() { return self.createImeiTab(modem); }
			},
			'NeighborCell': {
				name: _('Neighbor Cell'),
				handler: function() { return self.createNeighborCellTab(modem); }
			},
			'LockBand': {
				name: _('Lock Band'),
				handler: function() { return self.createLockBandTab(modem); }
			},
			'RebootModem': {
				name: _('Reboot Modem'),
				handler: function() { return self.createRebootModemTab(modem); }
			}
		};

		// Filter out disabled features
		var enabledFeatures = {};
		for (var key in features) {
			if (!disabledFeatures.includes(key)) {
				enabledFeatures[key] = features[key];
			}
		}

		// If no features enabled, show message
		if (Object.keys(enabledFeatures).length === 0) {
			return E('div', { 'class': 'alert-message warning' }, 
				_('No features available for this modem.'));
		}

		// Create tab menu
		var tabMenu = E('ul', { 'class': 'cbi-tabmenu' });
		var tabContentContainer = E('div', { 'id': 'tab_content_container' });

		var firstTab = null;
		var tabContents = {};

		Object.keys(enabledFeatures).forEach(function(key, index) {
			var feature = enabledFeatures[key];
			
			// Create tab button
			var tabButton = E('li', {
				'class': index === 0 ? 'cbi-tab' : 'cbi-tab-disabled',
				'data-tab': key,
				'click': function(ev) {
					// Switch active tab
					tabMenu.querySelectorAll('li').forEach(function(tab) {
						tab.classList.remove('cbi-tab');
						tab.classList.add('cbi-tab-disabled');
					});
					ev.target.classList.remove('cbi-tab-disabled');
					ev.target.classList.add('cbi-tab');
					
					// Show corresponding content
					for (var k in tabContents) {
						tabContents[k].style.display = 'none';
					}
					tabContents[key].style.display = '';
				}
			}, feature.name);
			
			tabMenu.appendChild(tabButton);
			
			// Create tab content (lazy loaded)
			var tabContent = E('div', {
				'class': 'cbi-section-node',
				'data-tab-content': key,
				'style': index === 0 ? '' : 'display: none;'
			});
			
			// Lazy load content when first shown
			if (index === 0) {
				dom.append(tabContent, feature.handler());
			} else {
				// Add lazy loading
				tabButton.addEventListener('click', function() {
					if (!tabContent.dataset.loaded) {
						dom.content(tabContent, feature.handler());
						tabContent.dataset.loaded = 'true';
					}
				}, { once: false });
			}
			
			tabContents[key] = tabContent;
		});

		container.appendChild(tabMenu);
		
		// Append all tab contents
		for (var key in tabContents) {
			tabContentContainer.appendChild(tabContents[key]);
		}
		container.appendChild(tabContentContainer);

		return container;
	},

	createDialModeTab: function(modem) {
		var self = this;
		var container = E('fieldset', { 'class': 'cbi-section' });
		var legend = E('legend', {}, _('Dial Mode Configuration'));
		container.appendChild(legend);

		var description = E('div', { 'class': 'cbi-section-descr' }, 
			_('Configure the modem dial mode (QMI/MBIM/ECM/NCM, etc.). Changes require modem reboot to take effect.'));
		container.appendChild(description);

		// Current mode display
		var currentModeSection = E('div', { 'class': 'cbi-value' });
		currentModeSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Current Mode')));
		var currentModeField = E('div', { 'class': 'cbi-value-field' });
		var currentModeValue = E('strong', { 'id': 'current_mode_' + modem.id }, _('Loading...'));
		currentModeField.appendChild(currentModeValue);
		currentModeSection.appendChild(currentModeField);
		container.appendChild(currentModeSection);

		// Mode selection section
		var modeSelectionSection = E('div', { 'class': 'cbi-value' });
		modeSelectionSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Select Mode')));
		var modeSelectionField = E('div', { 
			'class': 'cbi-value-field',
			'id': 'mode_selection_' + modem.id
		});
		modeSelectionField.appendChild(E('div', { 'class': 'spinning' }, _('Loading available modes...')));
		modeSelectionSection.appendChild(modeSelectionField);
		container.appendChild(modeSelectionSection);

		// Submit button section
		var buttonSection = E('div', { 'class': 'cbi-value' });
		buttonSection.appendChild(E('label', { 'class': 'cbi-value-title' }, ''));
		var buttonField = E('div', { 'class': 'cbi-value-field' });
		var submitButton = E('button', {
			'class': 'btn cbi-button-action',
			'id': 'submit_mode_' + modem.id,
			'disabled': true,
			'click': function() {
				var selectedMode = null;
				var radios = document.querySelectorAll('input[name="mode_' + modem.id + '"]');
				for (var i = 0; i < radios.length; i++) {
					if (radios[i].checked) {
						selectedMode = radios[i].value;
						break;
					}
				}

				if (!selectedMode) {
					ui.addNotification(null, E('p', _('Please select a mode')), 'error');
					return;
				}

				submitButton.disabled = true;
				submitButton.textContent = _('Applying...');

				qmodem.setMode(modem.id, selectedMode).then(function(result) {
					if (result && result.result) {
						ui.addNotification(null, E('p', _('Mode set successfully. Please reboot the modem.')), 'success');
						// Refresh the mode display
						self.loadDialMode(modem, currentModeValue, modeSelectionField, submitButton);
					} else {
						ui.addNotification(null, E('p', _('Failed to set mode')), 'error');
						submitButton.disabled = false;
						submitButton.textContent = _('Apply');
					}
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Error: %s').format(e.message)), 'error');
					submitButton.disabled = false;
					submitButton.textContent = _('Apply');
				});
			}
		}, _('Apply'));
		buttonField.appendChild(submitButton);
		buttonSection.appendChild(buttonField);
		container.appendChild(buttonSection);

		// Load current mode
		self.loadDialMode(modem, currentModeValue, modeSelectionField, submitButton);

		return container;
	},

	loadDialMode: function(modem, currentModeValue, modeSelectionField, submitButton) {
		qmodem.getMode(modem.id).then(function(result) {
			if (!result || !result.mode) {
				currentModeValue.textContent = _('Error loading mode');
				dom.content(modeSelectionField, E('em', {}, _('Failed to load available modes')));
				return;
			}

			var modes = result.mode;
			var currentMode = null;
			var availableModes = [];

			// Find current mode and available modes
			for (var mode in modes) {
				availableModes.push(mode);
				if (modes[mode] === '1' || modes[mode] === 1) {
					currentMode = mode;
				}
			}

			// Update current mode display
			currentModeValue.textContent = currentMode || _('Unknown');

			// Create radio buttons for mode selection
			if (availableModes.length === 0) {
				dom.content(modeSelectionField, E('em', {}, _('No modes available')));
				return;
			}

			var radioContainer = E('div', { 'class': 'cbi-value-field' });
			availableModes.forEach(function(mode) {
				var radioWrapper = E('div', { 'style': 'margin: 5px 0; display: flex;' });
				var radio = E('input', {
					'type': 'radio',
					'name': 'mode_' + modem.id,
					'value': mode,
					'id': 'mode_' + modem.id + '_' + mode,
					'checked': mode === currentMode ? 'checked' : null
				});
				var label = E('label', {
					'for': 'mode_' + modem.id + '_' + mode,
					'style': 'margin-left: 5px;'
				}, mode.toUpperCase());
				
				radioWrapper.appendChild(radio);
				radioWrapper.appendChild(label);
				radioContainer.appendChild(radioWrapper);
			});

			dom.content(modeSelectionField, radioContainer);
			submitButton.disabled = false;

		}).catch(function(e) {
			currentModeValue.textContent = _('Error');
			dom.content(modeSelectionField, E('div', { 'class': 'alert-message error' },
				_('Error loading mode: %s').format(e.message)));
		});
	},

	createRatPreferTab: function(modem) {
		var self = this;
		var container = E('fieldset', { 'class': 'cbi-section' });
		var legend = E('legend', {}, _('Network Preference Configuration'));
		container.appendChild(legend);

		var description = E('div', { 'class': 'cbi-section-descr' }, 
			_('Configure network preference (5G/4G/3G priority). Changes may require modem restart.'));
		container.appendChild(description);

		// Current network preference display
		var currentPrefSection = E('div', { 'class': 'cbi-value' });
		currentPrefSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Current Preference')));
		var currentPrefField = E('div', { 'class': 'cbi-value-field' });
		var currentPrefValue = E('strong', { 'id': 'current_pref_' + modem.id }, _('Loading...'));
		currentPrefField.appendChild(currentPrefValue);
		currentPrefSection.appendChild(currentPrefField);
		container.appendChild(currentPrefSection);

		// Network selection section
		var prefSelectionSection = E('div', { 'class': 'cbi-value' });
		prefSelectionSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Select Networks')));
		var prefSelectionField = E('div', { 
			'class': 'cbi-value-field',
			'id': 'pref_selection_' + modem.id
		});
		prefSelectionField.appendChild(E('div', { 'class': 'spinning' }, _('Loading available networks...')));
		prefSelectionSection.appendChild(prefSelectionField);
		container.appendChild(prefSelectionSection);

		// Submit button section
		var buttonSection = E('div', { 'class': 'cbi-value' });
		buttonSection.appendChild(E('label', { 'class': 'cbi-value-title' }, ''));
		var buttonField = E('div', { 'class': 'cbi-value-field' });
		var submitButton = E('button', {
			'class': 'btn cbi-button-action',
			'id': 'submit_pref_' + modem.id,
			'disabled': true,
			'click': function() {
				var selectedNetworks = [];
				var checkboxes = document.querySelectorAll('input[name="network_' + modem.id + '"]:checked');
				checkboxes.forEach(function(cb) {
					selectedNetworks.push(cb.value);
				});

				if (selectedNetworks.length === 0) {
					ui.addNotification(null, E('p', _('Please select at least one network type')), 'error');
					return;
				}

				submitButton.disabled = true;
				submitButton.textContent = _('Applying...');

				qmodem.setNetworkPrefer(modem.id, selectedNetworks).then(function(result) {
					if (result) {
						ui.addNotification(null, E('p', _('Network preference set successfully')), 'success');
						// Refresh the preference display
						self.loadNetworkPrefer(modem, currentPrefValue, prefSelectionField, submitButton);
					} else {
						ui.addNotification(null, E('p', _('Failed to set network preference')), 'error');
						submitButton.disabled = false;
						submitButton.textContent = _('Apply');
					}
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Error: %s').format(e.message)), 'error');
					submitButton.disabled = false;
					submitButton.textContent = _('Apply');
				});
			}
		}, _('Apply'));
		buttonField.appendChild(submitButton);
		buttonSection.appendChild(buttonField);
		container.appendChild(buttonSection);

		// Load current network preference
		self.loadNetworkPrefer(modem, currentPrefValue, prefSelectionField, submitButton);

		return container;
	},

	loadNetworkPrefer: function(modem, currentPrefValue, prefSelectionField, submitButton) {
		qmodem.getNetworkPrefer(modem.id).then(function(result) {
			if (!result || !result.network_prefer) {
				currentPrefValue.textContent = _('Error loading preference');
				dom.content(prefSelectionField, E('em', {}, _('Failed to load network preferences')));
				return;
			}

			var networkPrefer = result.network_prefer;
			var currentNetworks = [];
			var availableNetworks = [];

			// Find current and available networks
			for (var network in networkPrefer) {
				availableNetworks.push(network);
				if (networkPrefer[network] === '1' || networkPrefer[network] === 1) {
					currentNetworks.push(network);
				}
			}

			// Update current preference display
			currentPrefValue.textContent = currentNetworks.length > 0 ? currentNetworks.join(', ') : _('None');

			// Create checkboxes for network selection
			if (availableNetworks.length === 0) {
				dom.content(prefSelectionField, E('em', {}, _('No network types available')));
				return;
			}

			var checkboxContainer = E('div', { 'class': 'cbi-value-field' });
			availableNetworks.forEach(function(network) {
				var checkboxWrapper = E('div', { 'style': 'margin: 5px 0;' });
				var checkbox = E('input', {
					'type': 'checkbox',
					'name': 'network_' + modem.id,
					'value': network,
					'id': 'network_' + modem.id + '_' + network,
					'checked': networkPrefer[network] === '1' || networkPrefer[network] === 1 ? 'checked' : null
				});
				var label = E('label', {
					'for': 'network_' + modem.id + '_' + network,
					'style': 'margin-left: 5px;'
				}, network);
				
				checkboxWrapper.appendChild(checkbox);
				checkboxWrapper.appendChild(label);
				checkboxContainer.appendChild(checkboxWrapper);
			});

			dom.content(prefSelectionField, checkboxContainer);
			submitButton.disabled = false;

		}).catch(function(e) {
			currentPrefValue.textContent = _('Error');
			dom.content(prefSelectionField, E('div', { 'class': 'alert-message error' },
				_('Error loading network preference: %s').format(e.message)));
		});
	},

	createImeiTab: function(modem) {
		var self = this;
		var container = E('fieldset', { 'class': 'cbi-section' });
		var legend = E('legend', {}, _('IMEI Configuration'));
		container.appendChild(legend);

		var description = E('div', { 'class': 'cbi-section-descr' }, 
			_('View and modify the modem IMEI number. IMEI must be 15 digits. Changes require modem reboot to take effect.'));
		container.appendChild(description);

		// Current IMEI display
		var currentImeiSection = E('div', { 'class': 'cbi-value' });
		currentImeiSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Current IMEI')));
		var currentImeiField = E('div', { 'class': 'cbi-value-field' });
		var currentImeiValue = E('strong', { 
			'id': 'current_imei_' + modem.id,
			'style': 'font-family: monospace; font-size: 1.1em;'
		}, _('Loading...'));
		currentImeiField.appendChild(currentImeiValue);
		currentImeiSection.appendChild(currentImeiField);
		container.appendChild(currentImeiSection);

		// New IMEI input section
		var newImeiSection = E('div', { 'class': 'cbi-value' });
		newImeiSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('New IMEI')));
		var newImeiField = E('div', { 'class': 'cbi-value-field' });
		var imeiInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'id': 'imei_input_' + modem.id,
			'placeholder': '123456789012345',
			'maxlength': '15',
			'pattern': '[0-9]{15}',
			'style': 'font-family: monospace;'
		});
		
		// Add input validation
		imeiInput.addEventListener('input', function() {
			// Remove non-numeric characters
			this.value = this.value.replace(/[^0-9]/g, '');
			
			// Update validation state
			var submitButton = document.getElementById('submit_imei_' + modem.id);
			if (this.value.length === 15) {
				this.style.borderColor = '';
				if (submitButton) submitButton.disabled = false;
			} else {
				this.style.borderColor = 'red';
				if (submitButton) submitButton.disabled = true;
			}
		});

		var hint = E('div', { 
			'class': 'cbi-value-description',
			'style': 'margin-top: 5px;'
		}, _('Enter exactly 15 digits'));
		
		newImeiField.appendChild(imeiInput);
		newImeiField.appendChild(hint);
		newImeiSection.appendChild(newImeiField);
		container.appendChild(newImeiSection);

		// Submit button section
		var buttonSection = E('div', { 'class': 'cbi-value' });
		buttonSection.appendChild(E('label', { 'class': 'cbi-value-title' }, ''));
		var buttonField = E('div', { 'class': 'cbi-value-field' });
		
		var submitButton = E('button', {
			'class': 'btn cbi-button-action',
			'id': 'submit_imei_' + modem.id,
			'disabled': true,
			'click': function() {
				var newImei = imeiInput.value.trim();
				
				if (newImei.length !== 15) {
					ui.addNotification(null, E('p', _('IMEI must be exactly 15 digits')), 'error');
					return;
				}

				if (!/^[0-9]{15}$/.test(newImei)) {
					ui.addNotification(null, E('p', _('IMEI must contain only numbers')), 'error');
					return;
				}

				// Confirm before setting
				if (!confirm(_('Are you sure you want to change the IMEI to %s? This requires modem reboot.').format(newImei))) {
					return;
				}

				submitButton.disabled = true;
				submitButton.textContent = _('Setting...');

				qmodem.setImei(modem.id, newImei).then(function(result) {
					if (result && result.result) {
						ui.addNotification(null, E('p', _('IMEI set successfully. Please reboot the modem for changes to take effect.')), 'success');
						// Refresh the IMEI display
						self.loadImei(modem, currentImeiValue, imeiInput, submitButton);
					} else {
						ui.addNotification(null, E('p', _('Failed to set IMEI')), 'error');
						submitButton.disabled = false;
						submitButton.textContent = _('Apply');
					}
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Error: %s').format(e.message)), 'error');
					submitButton.disabled = false;
					submitButton.textContent = _('Apply');
				});
			}
		}, _('Apply'));
		
		buttonField.appendChild(submitButton);
		
		// Add warning message
		var warningDiv = E('div', { 
			'class': 'alert-message warning',
			'style': 'margin-top: 10px;'
		}, [
			E('strong', {}, _('Warning: ')),
			_('Changing IMEI may be illegal in some countries. Use at your own risk.')
		]);
		buttonField.appendChild(warningDiv);
		
		buttonSection.appendChild(buttonField);
		container.appendChild(buttonSection);

		// Load current IMEI
		self.loadImei(modem, currentImeiValue, imeiInput, submitButton);

		return container;
	},

	loadImei: function(modem, currentImeiValue, imeiInput, submitButton) {
		qmodem.getImei(modem.id).then(function(result) {
			if (!result || !result.imei) {
				currentImeiValue.textContent = _('Error loading IMEI');
				return;
			}

			var imei = result.imei;
			currentImeiValue.textContent = imei || _('Not available');
			
			// Pre-fill input with current IMEI for easy editing
			if (imei && imei.length === 15) {
				imeiInput.value = imei;
				imeiInput.dispatchEvent(new Event('input'));
			}

		}).catch(function(e) {
			currentImeiValue.textContent = _('Error');
			ui.addNotification(null, E('p', _('Error loading IMEI: %s').format(e.message)), 'error');
		});
	},

	createNeighborCellTab: function(modem) {
		var self = this;
		var container = E('fieldset', { 'class': 'cbi-section' });
		var legend = E('legend', {}, _('Neighbor Cell / Lock Cell'));
		container.appendChild(legend);

		var description = E('div', { 'class': 'cbi-section-descr' }, 
			_('Scan neighboring cell towers and lock modem to specific cell. You can scan for nearby cells and then lock to a specific cell by copying its parameters.'));
		container.appendChild(description);

		// Create three sections: Neighbor Cell List, Lock Cell Status, Lock Cell Settings
		
		// 1. Neighbor Cell List Section
		var neighborSection = E('div', { 
			'class': 'cbi-section',
			'style': 'margin-bottom: 20px;'
		});
		var neighborHeader = E('h3', { 'style': 'margin: 10px 0;' }, _('Neighbor Cell List'));
		neighborSection.appendChild(neighborHeader);
		
		var scanButton = E('button', {
			'class': 'btn cbi-button-action',
			'id': 'scan_neighbor_' + modem.id,
			'style': 'margin-bottom: 10px;',
			'click': function() {
				scanButton.disabled = true;
				scanButton.textContent = _('Scanning...');
				dom.content(neighborList, E('div', { 'class': 'spinning' }, _('Scanning neighbor cells...')));
				
				self.scanNeighborCell(modem, neighborList, scanButton);
			}
		}, _('Scan Neighbor Cells'));
		neighborSection.appendChild(scanButton);
		
		var neighborList = E('div', { 
			'id': 'neighbor_list_' + modem.id,
			'style': 'margin-top: 10px;'
		});
		neighborList.appendChild(E('em', {}, _('Click "Scan Neighbor Cells" to search for nearby cell towers')));
		neighborSection.appendChild(neighborList);
		container.appendChild(neighborSection);

		// 2. Lock Cell Status Section
		var statusSection = E('div', { 
			'class': 'cbi-section',
			'style': 'margin-bottom: 20px;'
		});
		var statusHeader = E('h3', { 'style': 'margin: 10px 0;' }, _('Lock Cell Status'));
		statusSection.appendChild(statusHeader);
		
		var statusContent = E('div', { 
			'id': 'lockcell_status_' + modem.id,
			'class': 'cbi-value-field'
		});
		statusContent.appendChild(E('em', {}, _('No status information available')));
		statusSection.appendChild(statusContent);
		container.appendChild(statusSection);

		// 3. Lock Cell Settings Section
		var settingsSection = E('div', { 'class': 'cbi-section' });
		var settingsHeader = E('h3', { 'style': 'margin: 10px 0;' }, _('Lock Cell Settings'));
		settingsSection.appendChild(settingsHeader);

		var settingsDesc = E('div', { 
			'class': 'cbi-value-description',
			'style': 'margin-bottom: 15px;'
		}, _('Configure cell lock parameters. You can manually enter values or use the "Copy" button from scanned cells.'));
		settingsSection.appendChild(settingsDesc);

		// RAT Selection
		var ratSection = E('div', { 'class': 'cbi-value' });
		ratSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('RAT')));
		var ratField = E('div', { 'class': 'cbi-value-field' });
		var ratSelect = E('select', {
			'class': 'cbi-input-select',
			'id': 'rat_select_' + modem.id,
			'change': function() {
				// Show/hide NR-specific fields
				var isNR = this.value === '1';
				bandRow.style.display = isNR ? '' : 'none';
				scsRow.style.display = isNR ? '' : 'none';
			}
		});
		ratSelect.appendChild(E('option', { 'value': '0' }, 'LTE'));
		ratSelect.appendChild(E('option', { 'value': '1' }, 'NR'));
		ratField.appendChild(ratSelect);
		ratSection.appendChild(ratField);
		settingsSection.appendChild(ratSection);

		// PCI Input
		var pciSection = E('div', { 'class': 'cbi-value' });
		pciSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('PCI')));
		var pciField = E('div', { 'class': 'cbi-value-field' });
		var pciInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'id': 'pci_input_' + modem.id,
			'placeholder': _('Physical Cell ID')
		});
		pciField.appendChild(pciInput);
		pciSection.appendChild(pciField);
		settingsSection.appendChild(pciSection);

		// ARFCN Input
		var arfcnSection = E('div', { 'class': 'cbi-value' });
		arfcnSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('ARFCN')));
		var arfcnField = E('div', { 'class': 'cbi-value-field' });
		var arfcnInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'id': 'arfcn_input_' + modem.id,
			'placeholder': _('Absolute Radio Frequency Channel Number')
		});
		arfcnField.appendChild(arfcnInput);
		arfcnSection.appendChild(arfcnField);
		settingsSection.appendChild(arfcnSection);

		// Band Input (for NR only)
		var bandRow = E('div', { 
			'class': 'cbi-value',
			'style': 'display: none;'
		});
		bandRow.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Band')));
		var bandField = E('div', { 'class': 'cbi-value-field' });
		var bandInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'id': 'band_input_' + modem.id,
			'placeholder': _('NR Band') + ' (N41/41/5041)'
		});
		bandField.appendChild(bandInput);
		bandRow.appendChild(bandField);
		settingsSection.appendChild(bandRow);

		// SCS Selection (for NR only)
		var scsRow = E('div', { 
			'class': 'cbi-value',
			'style': 'display: none;'
		});
		scsRow.appendChild(E('label', { 'class': 'cbi-value-title' }, _('SCS')));
		var scsField = E('div', { 'class': 'cbi-value-field' });
		var scsSelect = E('select', {
			'class': 'cbi-input-select',
			'id': 'scs_select_' + modem.id
		});
		scsSelect.appendChild(E('option', { 'value': '0' }, '15KHZ'));
		scsSelect.appendChild(E('option', { 'value': '1' }, '30KHZ'));
		scsField.appendChild(scsSelect);
		scsRow.appendChild(scsField);
		settingsSection.appendChild(scsRow);

		// Boot hook option
		var bootHookSection = E('div', { 'class': 'cbi-value' });
		bootHookSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Boot Hook')));
		var bootHookField = E('div', { 'class': 'cbi-value-field' });
		var bootHookCheckbox = E('input', {
			'type': 'checkbox',
			'id': 'boot_hook_lockcell_' + modem.id
		});
		bootHookField.appendChild(bootHookCheckbox);
		bootHookField.appendChild(E('span', { 'style': 'margin-left: 6px;' },
			_('Reapply lock cell command after modem initialization')));
		bootHookSection.appendChild(bootHookField);
		settingsSection.appendChild(bootHookSection);

		// Submit Button
		var buttonSection = E('div', { 'class': 'cbi-value' });
		buttonSection.appendChild(E('label', { 'class': 'cbi-value-title' }, ''));
		var buttonField = E('div', { 'class': 'cbi-value-field' });
		var unlockButton = E('button', {
			'class': 'btn cbi-button-action',
			'id': 'unlock_button_' + modem.id,
			'style': 'margin-right: 10px;',
			'click': function() {
				// Unlock cell
				var btn = this;
				btn.disabled = true;
				btn.textContent = _('Unlocking...');
				// rpc call lockcell but arfcn and pci empty
				qmodem.setNeighborCell(modem.id, {
					rat: '0',
					pci: '',
					arfcn: '',
					band: '',
					scs: '',
					en_boot_hook: '0'
				}).then(function(result) {
					if (result) {
						ui.addNotification(null, E('p', _('Cell unlocked successfully')), 'success');
						//  Refresh status
						self.updateLockCellStatus(modem, statusContent);
						
					} else {
						ui.addNotification(null, E('p', _('Failed to unlock cell')), 'error');
					}
					btn.disabled = false;
					btn.textContent = _('Unlock Cell');
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Error: %s').format(e.message)), 'error');
					btn.disabled = false;
					btn.textContent = _('Unlock Cell');
				});
			}
		}, _('Unlock Cell'));
		buttonField.appendChild(unlockButton);
		var submitButton = E('button', {
			'class': 'btn cbi-button-action',
			'id': 'submit_lockcell_' + modem.id,
			'click': function() {
				var config = {
					rat: ratSelect.value,
					pci: pciInput.value.trim(),
					arfcn: arfcnInput.value.trim(),
					band: bandInput.value.trim(),
					scs: scsSelect.value,
					en_boot_hook: bootHookCheckbox.checked ? '1' : '0'
				};

				if (!config.pci || !config.arfcn) {
					ui.addNotification(null, E('p', _('PCI and ARFCN are required')), 'error');
					return;
				}

				if (config.rat === '1' && !config.band) {
					ui.addNotification(null, E('p', _('Band is required for NR')), 'error');
					return;
				}

				submitButton.disabled = true;
				submitButton.textContent = _('Applying...');

				qmodem.setNeighborCell(modem.id, config).then(function(result) {
					if (result) {
						ui.addNotification(null, E('p', _('Lock cell configuration applied successfully')), 'success');
						// Refresh status
						self.updateLockCellStatus(modem, statusContent);
					} else {
						ui.addNotification(null, E('p', _('Failed to apply lock cell configuration')), 'error');
					}
					submitButton.disabled = false;
					submitButton.textContent = _('Apply');
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Error: %s').format(e.message)), 'error');
					submitButton.disabled = false;
					submitButton.textContent = _('Apply');
				});
			}
		}, _('Apply'));
		buttonField.appendChild(submitButton);
		buttonSection.appendChild(buttonField);
		settingsSection.appendChild(buttonSection);

		container.appendChild(settingsSection);

		// Store references for copy functionality
		this.neighborCellInputs = this.neighborCellInputs || {};
		this.neighborCellInputs[modem.id] = {
			rat: ratSelect,
			pci: pciInput,
			arfcn: arfcnInput,
			band: bandInput,
			scs: scsSelect,
			bootHook: bootHookCheckbox,
			bandRow: bandRow,
			scsRow: scsRow
		};

		self.updateLockCellStatus(modem, statusContent);

		return container;
	},

	scanNeighborCell: function(modem, neighborList, scanButton) {
		var self = this;
		
		qmodem.getNeighborCell(modem.id).then(function(result) {
			if (!result) {
				dom.content(neighborList, E('div', { 'class': 'alert-message warning' },
					_('No result returned from neighbor cell scan')));
				scanButton.disabled = false;
				scanButton.textContent = _('Scan Neighbor Cells');
				return;
			}
			result = result.neighborcell;
			var nrCells = result.NR || [];
			var lteCells = result.LTE || [];
			var lockcellStatus = result.lockcell_status || {};
			var bootHookStatus = result.lockcell_boot_hook || {};

			// Update status section
			var statusContent = document.getElementById('lockcell_status_' + modem.id);
			if (statusContent) {
				self.updateLockCellStatus(modem, statusContent, lockcellStatus, bootHookStatus);
			}

			if (nrCells.length === 0 && lteCells.length === 0) {
				dom.content(neighborList, E('div', { 'class': 'alert-message info' },
					_('No neighbor cells found. Make sure the modem has network signal.')));
				scanButton.disabled = false;
				scanButton.textContent = _('Scan Neighbor Cells');
				return;
			}

			var container = E('div', {});

			// Display LTE Cells
			if (lteCells.length > 0) {
				var lteSection = E('div', { 'class': 'cbi-section' });
				var lteHeader = E('h4', { 'style': 'margin: 10px 0 5px 0;' }, _('LTE Cells'));
				lteSection.appendChild(lteHeader);
				
				var lteTable = E('table', { 'class': 'table cbi-section-table' });
				var lteThead = E('thead', {});
				var lteHeaderRow = E('tr', { 'class': 'tr cbi-section-table-titles' });
				lteHeaderRow.appendChild(E('th', { 'class': 'th cbi-section-table-cell' }, _('RAT')));
				lteHeaderRow.appendChild(E('th', { 'class': 'th cbi-section-table-cell' }, _('Cell Information')));
				lteHeaderRow.appendChild(E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 10%;' }, _('Action')));
				lteThead.appendChild(lteHeaderRow);
				lteTable.appendChild(lteThead);
				
				var lteTbody = E('tbody', {});
				lteCells.forEach(function(cell) {
					var row = self.createNeighborCellRow(modem, 'LTE', cell, 0);
					lteTbody.appendChild(row);
				});
				lteTable.appendChild(lteTbody);
				lteSection.appendChild(lteTable);
				container.appendChild(lteSection);
			}

			// Display NR Cells
			if (nrCells.length > 0) {
				var nrSection = E('div', { 'class': 'cbi-section', 'style': 'margin-top: 15px;' });
				var nrHeader = E('h4', { 'style': 'margin: 10px 0 5px 0;' }, _('NR (5G) Cells'));
				nrSection.appendChild(nrHeader);
				
				var nrTable = E('table', { 'class': 'table cbi-section-table' });
				var nrThead = E('thead', {});
				var nrHeaderRow = E('tr', { 'class': 'tr cbi-section-table-titles' });
				nrHeaderRow.appendChild(E('th', { 'class': 'th cbi-section-table-cell' }, _('RAT')));
				nrHeaderRow.appendChild(E('th', { 'class': 'th cbi-section-table-cell' }, _('Cell Information')));
				nrHeaderRow.appendChild(E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 10%;' }, _('Action')));
				nrThead.appendChild(nrHeaderRow);
				nrTable.appendChild(nrThead);
				
				var nrTbody = E('tbody', {});
				nrCells.forEach(function(cell) {
					var row = self.createNeighborCellRow(modem, 'NR', cell, 1);
					nrTbody.appendChild(row);
				});
				nrTable.appendChild(nrTbody);
				nrSection.appendChild(nrTable);
				container.appendChild(nrSection);
			}

			dom.content(neighborList, container);
			scanButton.disabled = false;
			scanButton.textContent = _('Scan Neighbor Cells');

		}).catch(function(e) {
			console.error('getNeighborCell error:', e);
			dom.content(neighborList, E('div', { 'class': 'alert-message error' },
				_('Error scanning neighbor cells: %s').format(e.message || e.toString())));
			scanButton.disabled = false;
			scanButton.textContent = _('Scan Neighbor Cells');
		});
	},

	createNeighborCellRow: function(modem, ratType, cellInfo, ratValue) {
		var self = this;
		
		var row = E('tr', { 'class': 'tr cbi-section-table-row' });

		// RAT column
		var ratCell = E('td', { 'class': 'td cbi-section-table-cell' });
		var ratBadge = E('span', { 
			'class': 'label',
			'style': 'padding: 2px 8px; border-radius: 3px; font-weight: bold; ' + 
				(ratType === 'NR' ? 'background-color: #4CAF50; color: white;' : 'background-color: #2196F3; color: white;')
		}, ratType);
		ratCell.appendChild(ratBadge);
		row.appendChild(ratCell);

		// Cell info column
		var infoCell = E('td', { 'class': 'td cbi-section-table-cell' });
		var infoParts = [];
		for (var key in cellInfo) {
			if (cellInfo[key] !== '' && cellInfo[key] !== null && cellInfo[key] !== undefined) {
				infoParts.push(E('span', { 'style': 'margin-right: 10px;' }, [
					E('strong', {}, key + ': '),
					E('span', { 'style': 'font-family: monospace;' }, cellInfo[key].toString())
				]));
			}
		}
		var infoWrapper = E('div', { 'style': 'display: flex; flex-wrap: wrap;' });
		infoParts.forEach(function(part) {
			infoWrapper.appendChild(part);
		});
		infoCell.appendChild(infoWrapper);
		row.appendChild(infoCell);

		// Action column
		var actionCell = E('td', { 'class': 'td cbi-section-table-cell' });
		var copyButton = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'click': function() {
				if (!self.neighborCellInputs || !self.neighborCellInputs[modem.id]) {
					ui.addNotification(null, E('p', _('Configuration inputs not found')), 'error');
					return;
				}

				var inputs = self.neighborCellInputs[modem.id];
				inputs.rat.value = ratValue.toString();
				inputs.pci.value = cellInfo.pci || '';
				inputs.arfcn.value = cellInfo.arfcn || '';
				inputs.band.value = cellInfo.band || '';
				
				// Show/hide NR fields based on RAT
				if (ratValue === 1) {
					inputs.bandRow.style.display = '';
					inputs.scsRow.style.display = '';
				} else {
					inputs.bandRow.style.display = 'none';
					inputs.scsRow.style.display = 'none';
				}

				ui.addNotification(null, E('p', _('Cell parameters copied to settings')), 'info');
			}
		}, _('Copy'));
		actionCell.appendChild(copyButton);
		row.appendChild(actionCell);

		return row;
	},

	updateLockCellStatus: function(modem, statusContent, lockcellStatus, bootHookStatus) {
		var self = this;
		if (!lockcellStatus) {
			// Try to get fresh status
			qmodem.getNeighborCell(modem.id).then(function(result) {
				result = result && result.neighborcell;
				if (result && result.lockcell_status) {
					renderStatus(result.lockcell_status, result.lockcell_boot_hook || {});
				} else {
					dom.content(statusContent, E('em', {}, _('No status information available')));
				}
			}).catch(function(e) {
				dom.content(statusContent, E('em', {}, _('Error loading status')));
			});
			return;
		}

		function renderStatus(status, bootHookStatus) {
			var inputs = self.neighborCellInputs && self.neighborCellInputs[modem.id];
			if (inputs && inputs.bootHook && bootHookStatus) {
				inputs.bootHook.checked = !!bootHookStatus.enabled;
			}

			var statusItems = [];
			for (var key in status) {
				if (status[key] !== '' && status[key] !== null && status[key] !== undefined) {
					statusItems.push(key + ': ' + status[key].toString().toUpperCase());
				}
			}
			if (bootHookStatus && bootHookStatus.enabled) {
				statusItems.push(_('Boot Hook') + ': ' + _('Enabled') + ' (' +
					_('Delay') + ': ' + (bootHookStatus.delay || '15') + 's)');
			}

			if (statusItems.length === 0) {
				dom.content(statusContent, E('em', {}, _('Cell is unlocked (no lock active)')));
			} else {
				var statusDiv = E('div', {});
				statusItems.forEach(function(item) {
					statusDiv.appendChild(E('div', { 
						'style': 'padding: 3px 0;'
					}, item));
				});
				dom.content(statusContent, statusDiv);
			}
		}

		renderStatus(lockcellStatus, bootHookStatus || {});
	},

	createLockBandTab: function(modem) {
		var self = this;
		var container = E('fieldset', { 'class': 'cbi-section' });
		var legend = E('legend', {}, _('Lock Band Configuration'));
		container.appendChild(legend);

		var description = E('div', { 'class': 'cbi-section-descr' }, 
			_('Lock modem to specific frequency bands. Select bands for each network type (UMTS/LTE/NR).'));
		container.appendChild(description);

		// Lock band content area
		var lockbandContent = E('div', { 'id': 'lockband_content_' + modem.id });
		lockbandContent.appendChild(E('div', { 'class': 'spinning' }, _('Loading band configuration...')));
		container.appendChild(lockbandContent);

		// Load lockband configuration
		self.loadLockBand(modem, lockbandContent);

		return container;
	},

	loadLockBand: function(modem, lockbandContent) {
		var self = this;
		
		qmodem.getLockBand(modem.id).then(function(result) {
			
			if (!result) {
				dom.content(lockbandContent, E('div', { 'class': 'alert-message warning' },
					_('No result returned from getLockBand')));
				return;
			}

			// Handle different response structures
			var lockband = result.lockband || result;
			
			// Check if lockband is valid
			if (!lockband || typeof lockband !== 'object') {
				dom.content(lockbandContent, E('div', { 'class': 'alert-message warning' },
					_('Invalid lockband data structure')));
				return;
			}

			var bandClasses = Object.keys(lockband);

			// Filter out non-band-class keys
			bandClasses = bandClasses.filter(function(key) {
				return lockband[key] && typeof lockband[key] === 'object' &&
					   (lockband[key].available_band || lockband[key].lock_band);
			});

			if (bandClasses.length === 0) {
				dom.content(lockbandContent, E('div', { 'class': 'alert-message info' },
					_('No bands available for this modem')));
				return;
			}

			var container = E('div', {});

			// Store lockband state
			var lockbandState = {};

			bandClasses.forEach(function(bandClass) {
				var bandData = lockband[bandClass];
				
				// Ensure bandData has the expected structure
				if (!bandData || typeof bandData !== 'object') {
					console.warn('Invalid bandData for', bandClass, bandData);
					return;
				}
				
				// Get available_band (might be array or needs conversion)
				var availableBands = bandData.available_band || [];
				if (!Array.isArray(availableBands)) {
					console.warn('available_band is not an array for', bandClass);
					return;
				}
				
				if (availableBands.length === 0) {
					console.info('No available bands for', bandClass);
					return;
				}

				// Get locked bands (might be array or string)
				var lockedBands = bandData.lock_band || [];
				if (typeof lockedBands === 'string') {
					lockedBands = lockedBands.split(',').filter(function(b) { return b.length > 0; });
				}
				if (!Array.isArray(lockedBands)) {
					lockedBands = [];
				}

				// Initialize state for this band class
				lockbandState[bandClass] = {
					available: availableBands,
					locked: lockedBands
				};

				// Create section for this band class
				var bandSection = E('div', { 
					'class': 'cbi-section',
					'style': 'margin-bottom: 20px;'
				});

				var bandHeader = E('h3', { 
					'style': 'margin: 10px 0;'
				}, bandClass);
				bandSection.appendChild(bandHeader);

				// Current locked bands display
				var currentSection = E('div', { 
					'class': 'cbi-value',
					'style': 'margin-bottom: 10px;'
				});
				currentSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Locked Bands')));
				var currentField = E('div', { 'class': 'cbi-value-field' });
				var lockedDisplay = E('strong', { 
					'id': 'locked_' + modem.id + '_' + bandClass 
				});
				self.updateLockedDisplay(lockedDisplay, lockbandState[bandClass].locked, lockbandState[bandClass].available);
				currentField.appendChild(lockedDisplay);
				currentSection.appendChild(currentField);
				bandSection.appendChild(currentSection);

				// Band selection area
				var selectionSection = E('div', { 'class': 'cbi-value' });
				selectionSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Select Bands')));
				var selectionField = E('div', { 
					'class': 'cbi-value-field',
					'style': 'display: flex; flex-wrap: wrap;'
				});

				// Create checkboxes for each available band
				bandData.available_band.forEach(function(band) {
					var bandWrapper = E('div', { 
						'class': 'band-container',
						'style': 'display: flex; align-items: center; margin: 5px 15px 5px 0; min-width: 100px;'
					});

					var checkbox = E('input', {
						'type': 'checkbox',
						'name': 'band_' + modem.id + '_' + bandClass,
						'value': band.band_id,
						'id': 'band_' + modem.id + '_' + bandClass + '_' + band.band_id,
						'checked': lockbandState[bandClass].locked.includes(band.band_id.toString()) ? 'checked' : null,
						'change': function() {
							if (this.checked) {
								if (!lockbandState[bandClass].locked.includes(band.band_id.toString())) {
									lockbandState[bandClass].locked.push(band.band_id.toString());
								}
							} else {
								lockbandState[bandClass].locked = lockbandState[bandClass].locked.filter(function(b) {
									return b !== band.band_id.toString();
								});
							}
							self.updateLockedDisplay(lockedDisplay, lockbandState[bandClass].locked, bandData.available_band);
						}
					});

					var label = E('label', {
						'for': 'band_' + modem.id + '_' + bandClass + '_' + band.band_id,
						'style': 'margin-left: 5px; cursor: pointer;'
					}, band.band_name);

					bandWrapper.appendChild(checkbox);
					bandWrapper.appendChild(label);
					selectionField.appendChild(bandWrapper);
				});

				selectionSection.appendChild(selectionField);
				bandSection.appendChild(selectionSection);

				// Action buttons for this band class
				var buttonSection = E('div', { 
					'class': 'cbi-value',
					'style': 'margin-top: 10px;'
				});
				buttonSection.appendChild(E('label', { 'class': 'cbi-value-title' }, ''));
				var buttonField = E('div', { 'class': 'cbi-value-field' });

				// Select All button
				var selectAllBtn = E('button', {
					'class': 'btn cbi-button',
					'style': 'margin-right: 10px;',
					'click': function() {
						var allSelected = lockbandState[bandClass].locked.length === bandData.available_band.length;
						
						if (allSelected) {
							// Unselect all
							lockbandState[bandClass].locked = [];
							selectionField.querySelectorAll('input[type="checkbox"]').forEach(function(cb) {
								cb.checked = false;
							});
						} else {
							// Select all
							lockbandState[bandClass].locked = bandData.available_band.map(function(b) {
								return b.band_id.toString();
							});
							selectionField.querySelectorAll('input[type="checkbox"]').forEach(function(cb) {
								cb.checked = true;
							});
						}
						self.updateLockedDisplay(lockedDisplay, lockbandState[bandClass].locked, bandData.available_band);
					}
				}, _('Select All / None'));

				// Apply button
				var applyBtn = E('button', {
					'class': 'btn cbi-button-action',
					'click': function() {
						var params = {
							band_class: bandClass,
							lock_band: lockbandState[bandClass].locked.sort(function(a, b) {
								return parseInt(a) - parseInt(b);
							}).join(',')
						};

						applyBtn.disabled = true;
						applyBtn.textContent = _('Applying...');

						qmodem.setLockBand(modem.id, params).then(function(result) {
							if (result) {
								ui.addNotification(null, E('p', _('Lock band configuration applied for %s').format(bandClass)), 'success');
								// Refresh the display
								self.loadLockBand(modem, lockbandContent);
							} else {
								ui.addNotification(null, E('p', _('Failed to apply lock band configuration')), 'error');
								applyBtn.disabled = false;
								applyBtn.textContent = _('Apply');
							}
						}).catch(function(e) {
							ui.addNotification(null, E('p', _('Error: %s').format(e.message)), 'error');
							applyBtn.disabled = false;
							applyBtn.textContent = _('Apply');
						});
					}
				}, _('Apply'));

				buttonField.appendChild(selectAllBtn);
				buttonField.appendChild(applyBtn);
				buttonSection.appendChild(buttonField);
				bandSection.appendChild(buttonSection);

				container.appendChild(bandSection);
			});

			dom.content(lockbandContent, container);

		}).catch(function(e) {
			console.error('getLockBand error:', e);
			dom.content(lockbandContent, E('div', { 'class': 'alert-message error' }, [
				E('p', {}, _('Error loading lock band configuration:')),
				E('p', {}, e.message || e.toString()),
				E('p', { 'style': 'font-size: 0.9em; margin-top: 10px;' }, 
					_('Please check browser console for more details'))
			]));
		});
	},

	updateLockedDisplay: function(displayElement, lockedBands, availableBands) {
		if (lockedBands.length === 0) {
			displayElement.textContent = _('None (All bands unlocked)');
			displayElement.style.color = '';
			return;
		}

		// Create display with band names
		var bandNames = [];
		lockedBands.forEach(function(bandId) {
			var band = availableBands.find(function(b) {
				return b.band_id.toString() === bandId.toString();
			});
			if (band) {
				bandNames.push(band.band_name);
			} else {
				bandNames.push(bandId);
			}
		});

		displayElement.textContent = bandNames.join(', ');
		displayElement.style.color = '#0066cc';
	},

	createRebootModemTab: function(modem) {
		var self = this;
		var container = E('fieldset', { 'class': 'cbi-section' });
		var legend = E('legend', {}, _('Reboot Modem'));
		container.appendChild(legend);

		var description = E('div', { 'class': 'cbi-section-descr' }, 
			_('Reboot the modem device. Soft reboot restarts the modem firmware, hard reboot power cycles the modem.'));
		container.appendChild(description);

		// Reboot buttons section
		var rebootSection = E('div', { 'class': 'cbi-value' });
		rebootSection.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Reboot Options')));
		var rebootField = E('div', { 
			'class': 'cbi-value-field',
			'id': 'reboot_buttons_' + modem.id
		});
		rebootField.appendChild(E('div', { 'class': 'spinning' }, _('Loading reboot capabilities...')));
		rebootSection.appendChild(rebootField);
		container.appendChild(rebootSection);

		// Load reboot capabilities and create buttons
		self.loadRebootCaps(modem, rebootField);

		return container;
	},

	loadRebootCaps: function(modem, rebootField) {
		var self = this;
		
		qmodem.getRebootCaps(modem.id).then(function(result) {
			if (!result || !result.reboot_caps) {
				dom.content(rebootField, E('em', {}, _('Failed to load reboot capabilities')));
				return;
			}

			var caps = result.reboot_caps;
			var hasSoftReboot = caps.soft_reboot_caps === '1' || caps.soft_reboot_caps === 1;
			var hasHardReboot = caps.hard_reboot_caps === '1' || caps.hard_reboot_caps === 1;

			if (!hasSoftReboot && !hasHardReboot) {
				dom.content(rebootField, E('em', {}, _('No reboot methods available for this modem')));
				return;
			}

			var buttonContainer = E('div', {});

			// Soft Reboot Button
			if (hasSoftReboot) {
				var softRebootBtn = E('button', {
					'class': 'btn cbi-button-action',
					'id': 'soft_reboot_' + modem.id,
					'style': 'margin-right: 10px; margin-bottom: 10px;',
					'click': function() {
						if (!confirm(_('Are you sure you want to perform a soft reboot? The modem will restart and may lose connection temporarily.'))) {
							return;
						}

						softRebootBtn.disabled = true;
						softRebootBtn.textContent = _('Rebooting...');

						qmodem.doReboot(modem.id, 'soft').then(function(result) {
							if (result && result.result && result.result.status === '1') {
								ui.addNotification(null, E('p', _('Soft reboot initiated successfully. The modem is restarting...')), 'success');
								setTimeout(function() {
									softRebootBtn.disabled = false;
									softRebootBtn.textContent = _('Soft Reboot');
								}, 10000);
							} else {
								ui.addNotification(null, E('p', _('Failed to initiate soft reboot')), 'error');
								softRebootBtn.disabled = false;
								softRebootBtn.textContent = _('Soft Reboot');
							}
						}).catch(function(e) {
							ui.addNotification(null, E('p', _('Error: %s').format(e.message)), 'error');
							softRebootBtn.disabled = false;
							softRebootBtn.textContent = _('Soft Reboot');
						});
					}
				}, _('Soft Reboot'));
				
				buttonContainer.appendChild(softRebootBtn);
			}

			// Hard Reboot Button
			if (hasHardReboot) {
				var hardRebootBtn = E('button', {
					'class': 'btn cbi-button-negative',
					'id': 'hard_reboot_' + modem.id,
					'style': 'margin-bottom: 10px;',
					'click': function() {
						if (!confirm(_('Are you sure you want to perform a hard reboot? This will power cycle the modem and may cause a longer disconnection.'))) {
							return;
						}

						hardRebootBtn.disabled = true;
						hardRebootBtn.textContent = _('Rebooting...');

						qmodem.doReboot(modem.id, 'hard').then(function(result) {
							if (result && result.result && result.result.status === '1') {
								ui.addNotification(null, E('p', _('Hard reboot initiated successfully. The modem is restarting...')), 'success');
								setTimeout(function() {
									hardRebootBtn.disabled = false;
									hardRebootBtn.textContent = _('Hard Reboot');
								}, 15000);
							} else {
								ui.addNotification(null, E('p', _('Failed to initiate hard reboot')), 'error');
								hardRebootBtn.disabled = false;
								hardRebootBtn.textContent = _('Hard Reboot');
							}
						}).catch(function(e) {
							ui.addNotification(null, E('p', _('Error: %s').format(e.message)), 'error');
							hardRebootBtn.disabled = false;
							hardRebootBtn.textContent = _('Hard Reboot');
						});
					}
				}, _('Hard Reboot'));
				
				buttonContainer.appendChild(hardRebootBtn);
			}

			// Add descriptions
			var descContainer = E('div', { 'style': 'margin-top: 15px;' });
			
			if (hasSoftReboot) {
				descContainer.appendChild(E('div', { 'style': 'margin-bottom: 5px;' }, [
					E('strong', {}, _('Soft Reboot') + ': '),
					E('span', {}, _('Restarts the modem firmware without power cycling. Faster but may not resolve all issues.'))
				]));
			}
			
			if (hasHardReboot) {
				descContainer.appendChild(E('div', { 'style': 'margin-bottom: 5px;' }, [
					E('strong', {}, _('Hard Reboot') + ': '),
					E('span', {}, _('Power cycles the modem completely. Takes longer but ensures a full restart.'))
				]));
			}

			buttonContainer.appendChild(descContainer);
			dom.content(rebootField, buttonContainer);

		}).catch(function(e) {
			dom.content(rebootField, E('div', { 'class': 'alert-message error' },
				_('Error loading reboot capabilities: %s').format(e.message)));
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
