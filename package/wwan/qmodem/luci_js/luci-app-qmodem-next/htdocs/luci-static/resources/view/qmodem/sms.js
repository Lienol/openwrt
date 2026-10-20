'use strict';
'require view';
'require poll';
'require ui';
'require dom';
'require uci';
'require qmodem.sms as smsService';
'require qmodem.qmodem as qmodem';

// Load CSS
document.head.appendChild(E('link', {
	'rel': 'stylesheet',
	'type': 'text/css',
	'href': L.resource('qmodem/qmodem-next.css')
}));

return view.extend({
	// Timezone offset setting utilities
	getUtcOffsetSetting: function(type) {
		// type: 'received' or 'sent'
		var key = 'qmodem_sms_utc_offset_' + type;
		var setting = localStorage.getItem(key);
		return setting === 'true';
	},

	setUtcOffsetSetting: function(type, enabled) {
		// type: 'received' or 'sent'
		var key = 'qmodem_sms_utc_offset_' + type;
		localStorage.setItem(key, enabled ? 'true' : 'false');
	},

	adjustTimestampForUtcOffset: function(timestamp, type) {
		// If UTC offset is enabled for this message type, adjust the timestamp
		// PDU time is in local time (UTC+8), but parsed as UTC+0
		// So we need to subtract 8 hours to get the correct UTC time
		if (this.getUtcOffsetSetting(type)) {
			// Subtract 8 hours (28800 seconds)
			return timestamp - 28800;
		}
		return timestamp;
	},

	load: function() {
		return qmodem.getModemSections();
	},

	render: function(modems) {
		var self = this;
		var container = E('div', { 'class': 'cbi-map' });

		// Filter enabled modems
		modems = modems.filter(function(m) { return m.enabled; });

		if (modems.length === 0) {
			container.appendChild(E('div', { 'class': 'alert-message warning' }, 
				_('No modems configured or all modems are disabled.')));
			return container;
		}

		// Modem selector
		var selectorSection = E('fieldset', { 'class': 'cbi-section' });
		var selectorTable = E('table', { 'class': 'table' });
		var selectorBody = E('tbody', {});
		var selectorRow = E('tr', { 'class': 'tr' });
		var labelCell = E('td', { 'class': 'td', 'width': '33%' }, _('Modem Name'));
		var selectCell = E('td', { 'class': 'td' });
		
		var select = E('select', {
			'class': 'cbi-input-select',
			'id': 'sms_modem_selector'
		});
		
		modems.forEach(function(modem) {
			select.appendChild(E('option', { 'value': modem.id }, modem.name));
		});
		
		selectCell.appendChild(select);
		selectorRow.appendChild(labelCell);
		selectorRow.appendChild(selectCell);
		selectorBody.appendChild(selectorRow);

		// Timezone offset setting for received messages
		var timezoneReceivedRow = E('tr', { 'class': 'tr' });
		var timezoneReceivedLabel = E('td', { 'class': 'td', 'width': '33%' }, 
			_('Parse received SMS time as UTC+0'));
		var timezoneReceivedCell = E('td', { 'class': 'td' });
		
		var timezoneReceivedCheckbox = E('input', {
			'type': 'checkbox',
			'id': 'sms_utc_offset_received_checkbox'
		});
		if (self.getUtcOffsetSetting('received')) {
			timezoneReceivedCheckbox.checked = true;
		}
		
		timezoneReceivedCell.appendChild(timezoneReceivedCheckbox);
		timezoneReceivedCell.appendChild(E('span', { 'style': 'margin-left: 5px;' }, 
			_('Adjust received messages for local timezone (UTC+8)')));
		timezoneReceivedRow.appendChild(timezoneReceivedLabel);
		timezoneReceivedRow.appendChild(timezoneReceivedCell);
		selectorBody.appendChild(timezoneReceivedRow);

		// Timezone offset setting for sent messages
		var timezoneSentRow = E('tr', { 'class': 'tr' });
		var timezoneSentLabel = E('td', { 'class': 'td', 'width': '33%' }, 
			_('Parse sent SMS time as UTC+0'));
		var timezoneSentCell = E('td', { 'class': 'td' });
		
		var timezoneSentCheckbox = E('input', {
			'type': 'checkbox',
			'id': 'sms_utc_offset_sent_checkbox'
		});
		if (self.getUtcOffsetSetting('sent')) {
			timezoneSentCheckbox.checked = true;
		}
		
		var timezoneHelpText = E('div', {
			'style': 'font-size: 12px; color: #666; margin-top: 5px;'
		}, _('Enable if SMS timestamps appear 8 hours ahead (e.g., UTC+8 local time parsed as UTC+0)'));
		
		timezoneSentCell.appendChild(timezoneSentCheckbox);
		timezoneSentCell.appendChild(E('span', { 'style': 'margin-left: 5px;' }, 
			_('Adjust sent messages for local timezone (UTC+8)')));
	timezoneSentCell.appendChild(timezoneHelpText);
	timezoneSentRow.appendChild(timezoneSentLabel);
	timezoneSentRow.appendChild(timezoneSentCell);
	selectorBody.appendChild(timezoneSentRow);

	// SMS database path setting
	var smsDbPathRow = E('tr', { 'class': 'tr' });
	var smsDbPathLabel = E('td', { 'class': 'td', 'width': '33%' }, 
		_('SMS Database Path'));
	var smsDbPathCell = E('td', { 'class': 'td' });
	
	var smsDbPathInput = E('input', {
		'type': 'text',
		'class': 'cbi-input-text',
		'id': 'sms_db_path_input',
		'placeholder': '/etc/qmodem'
	});
	
	smsDbPathCell.appendChild(smsDbPathInput);
	smsDbPathCell.appendChild(E('div', {
		'style': 'font-size: 12px; color: #666; margin-top: 5px;'
	}, _('Path to SMS database file')));
	smsDbPathRow.appendChild(smsDbPathLabel);
	smsDbPathRow.appendChild(smsDbPathCell);
	selectorBody.appendChild(smsDbPathRow);

	// SMS auto delete from SIM setting
	var smsAutoDeleteRow = E('tr', { 'class': 'tr' });
	var smsAutoDeleteLabel = E('td', { 'class': 'td', 'width': '33%' }, 
		_('Auto Delete from SIM'));
	var smsAutoDeleteCell = E('td', { 'class': 'td' });
	
	var smsAutoDeleteCheckbox = E('input', {
		'type': 'checkbox',
		'id': 'sms_auto_delete_checkbox'
	});
	
	smsAutoDeleteCell.appendChild(smsAutoDeleteCheckbox);
	smsAutoDeleteCell.appendChild(E('span', { 'style': 'margin-left: 5px;' }, 
		_('Automatically delete SMS from SIM card after reading')));
	smsAutoDeleteRow.appendChild(smsAutoDeleteLabel);
	smsAutoDeleteRow.appendChild(smsAutoDeleteCell);
	selectorBody.appendChild(smsAutoDeleteRow);

	selectorTable.appendChild(selectorBody);
	selectorSection.appendChild(selectorTable);
	container.appendChild(selectorSection);

	// SMS Storage Section
	var storageSection = E('fieldset', { 'class': 'cbi-section' });
	var storageLegend = E('legend', {}, _('SMS Storage'));
	storageSection.appendChild(storageLegend);
	
	var storageTable = E('table', { 'class': 'table' });
	var storageBody = E('tbody', {});
	
	// Reading Storage
	var readingRow = E('tr', { 'class': 'tr' });
	var readingLabel = E('td', { 'class': 'td', 'width': '33%' }, _('Reading Storage'));
	var readingCell = E('td', { 'class': 'td' });
	var readingSelect = E('select', {
		'class': 'cbi-input-select',
		'id': 'sms_reading_storage'
	}, [
		E('option', { 'value': 'ME' }, _('Mobile Equipment (ME)')),
		E('option', { 'value': 'SM' }, _('SIM Card (SM)')),
		E('option', { 'value': 'Loading', 'selected': 'selected' }, _('Loading...'))
	]);
	readingCell.appendChild(readingSelect);
	readingRow.appendChild(readingLabel);
	readingRow.appendChild(readingCell);
	storageBody.appendChild(readingRow);
	
	// Writing Storage
	var writingRow = E('tr', { 'class': 'tr' });
	var writingLabel = E('td', { 'class': 'td', 'width': '33%' }, _('Writing Storage'));
	var writingCell = E('td', { 'class': 'td' });
	var writingSelect = E('select', {
		'class': 'cbi-input-select',
		'id': 'sms_writing_storage'
	}, [
		E('option', { 'value': 'ME' }, _('Mobile Equipment (ME)')),
		E('option', { 'value': 'SM' }, _('SIM Card (SM)')),
		E('option', { 'value': 'Loading', 'selected': 'selected' }, _('Loading...'))
	]);
	writingCell.appendChild(writingSelect);
	writingRow.appendChild(writingLabel);
	writingRow.appendChild(writingCell);
	storageBody.appendChild(writingRow);
	
	// ETC Storage
	var etcRow = E('tr', { 'class': 'tr' });
	var etcLabel = E('td', { 'class': 'td', 'width': '33%' }, _('Other Storage'));
	var etcCell = E('td', { 'class': 'td' });
	var etcSelect = E('select', {
		'class': 'cbi-input-select',
		'id': 'sms_etc_storage'
	}, [
		E('option', { 'value': 'ME' }, _('Mobile Equipment (ME)')),
		E('option', { 'value': 'SM' }, _('SIM Card (SM)')),
		E('option', { 'value': 'Loading', 'selected': 'selected' }, _('Loading...'))
	]);
	etcCell.appendChild(etcSelect);
	etcRow.appendChild(etcLabel);
	etcRow.appendChild(etcCell);
	storageBody.appendChild(etcRow);
	
	// Set Storage Button
	var setStorageRow = E('tr', { 'class': 'tr' });
	var setStorageLabel = E('td', { 'class': 'td', 'width': '33%' }, '');
	var setStorageCell = E('td', { 'class': 'td' });
	var setStorageBtn = E('button', {
		'class': 'cbi-button cbi-button-apply',
		'id': 'sms_set_storage_btn',
		'click': function(ev) {
			ev.preventDefault();
			self.setSmsStorage(select.value, readingSelect, writingSelect, etcSelect);
		}
	}, _('Apply Storage Settings'));
	setStorageCell.appendChild(setStorageBtn);
	setStorageRow.appendChild(setStorageLabel);
	setStorageRow.appendChild(setStorageCell);
	storageBody.appendChild(setStorageRow);
	
	storageTable.appendChild(storageBody);
	storageSection.appendChild(storageTable);
	container.appendChild(storageSection);
	
		// Title
		var title = E('h2', { 'name': 'content' }, _('SMS Messages'));
		container.appendChild(title);

		// Description
		var desc = E('div', { 'class': 'cbi-map-descr' }, 
			_('View and manage SMS messages. Messages are grouped by sender/recipient.'));
		container.appendChild(desc);

		// Main content area
		var contentArea = E('div', { 'id': 'sms-list-content' });
		container.appendChild(contentArea);

		// Loading indicator
		var loadingDiv = E('div', { 'class': 'spinning' }, _('Loading...'));
		contentArea.appendChild(loadingDiv);

	// Load SMS list with selected modem
	var selectedModem = select.value;
	
	// Load UCI config for selected modem
	this.loadUciConfig(selectedModem, smsDbPathInput, smsAutoDeleteCheckbox);
		// Load SMS storage info
	this.loadSmsStorage(selectedModem, readingSelect, writingSelect, etcSelect);
		this.loadSmsList(contentArea, loadingDiv, selectedModem);

	// Selector change handler
	select.addEventListener('change', function() {
		// Load UCI config for selected modem
		self.loadUciConfig(select.value, smsDbPathInput, smsAutoDeleteCheckbox);
		
		// Load SMS storage info
		self.loadSmsStorage(select.value, readingSelect, writingSelect, etcSelect);
		
		var loading = E('div', { 'class': 'spinning' }, _('Loading...'));
		dom.content(contentArea, loading);
		self.loadSmsList(contentArea, loading, select.value);
	});

		// Timezone checkbox change handler for received messages
		timezoneReceivedCheckbox.addEventListener('change', function() {
			self.setUtcOffsetSetting('received', timezoneReceivedCheckbox.checked);
			var loading = E('div', { 'class': 'spinning' }, _('Loading...'));
			dom.content(contentArea, loading);
			self.loadSmsList(contentArea, loading, select.value);
		});

	// Timezone checkbox change handler for sent messages
	timezoneSentCheckbox.addEventListener('change', function() {
		self.setUtcOffsetSetting('sent', timezoneSentCheckbox.checked);
		var loading = E('div', { 'class': 'spinning' }, _('Loading...'));
		dom.content(contentArea, loading);
		self.loadSmsList(contentArea, loading, select.value);
	});

	// SMS database path change handler
	smsDbPathInput.addEventListener('change', function() {
		self.saveUciOption(select.value, 'sms_db_path', smsDbPathInput.value);
	});

	// SMS auto delete checkbox change handler
	smsAutoDeleteCheckbox.addEventListener('change', function() {
		self.saveUciOption(select.value, 'sms_auto_delete_from_sim', smsAutoDeleteCheckbox.checked ? '1' : '0');
	});

	// Start polling for new messages
	poll.add(function() {
		self.pollSmsList(contentArea, select.value);
	}, 10);		return container;
	},

	loadSmsList: function(contentArea, loadingDiv, configSection) {
		var self = this;

		smsService.listSms(configSection).then(function(result) {
			// Adjust timestamps if UTC offset is enabled (based on message type)
			if (result.conversations && result.conversations.length > 0) {
				result.conversations.forEach(function(conv) {
					if (conv.messages && conv.messages.length > 0) {
						conv.messages.forEach(function(msg) {
							if (msg.timestamp && msg.type) {
								msg.timestamp = self.adjustTimestampForUtcOffset(msg.timestamp, msg.type);
							}
						});
						// Re-sort messages by timestamp
						conv.messages.sort(function(a, b) {
							return a.timestamp - b.timestamp;
						});
					}
				});
			}

			// Remove loading indicator
			if (loadingDiv && loadingDiv.parentNode) {
				dom.content(contentArea, null);
			}

			if (result.error) {
				contentArea.appendChild(E('div', { 'class': 'alert-message error' }, 
					_('Error loading SMS: ') + result.error));
				return;
			}

			// Render conversations list
			self.renderConversationsList(contentArea, result.conversations || [], configSection);
		}).catch(function(err) {
			if (loadingDiv && loadingDiv.parentNode) {
				dom.content(contentArea, null);
			}
			contentArea.appendChild(E('div', { 'class': 'alert-message error' }, 
				_('Failed to load SMS: ') + err.message));
		});
	},

	pollSmsList: function(contentArea, configSection) {
		var self = this;
		
		smsService.listSms(configSection).then(function(result) {
			if (!result.error && result.conversations) {
				// Adjust timestamps if UTC offset is enabled (based on message type)
				if (result.conversations.length > 0) {
					result.conversations.forEach(function(conv) {
						if (conv.messages && conv.messages.length > 0) {
							conv.messages.forEach(function(msg) {
								if (msg.timestamp && msg.type) {
									msg.timestamp = self.adjustTimestampForUtcOffset(msg.timestamp, msg.type);
								}
							});
							// Re-sort messages by timestamp
							conv.messages.sort(function(a, b) {
								return a.timestamp - b.timestamp;
							});
						}
					});
				}
				self.renderConversationsList(contentArea, result.conversations, configSection);
			}
		}).catch(function(err) {
			console.error('Poll error:', err);
		});
	},

	renderConversationsList: function(contentArea, conversations, configSection) {
		var self = this;

		// Clear content
		dom.content(contentArea, null);

		// Create conversations container
		var conversationsDiv = E('div', { 'class': 'sms-conversations' });

		if (!conversations || conversations.length === 0) {
			conversationsDiv.appendChild(E('div', { 'class': 'alert-message info' }, 
				_('No messages found')));
		} else {
			// Create conversations list
			var listDiv = E('div', { 'class': 'cbi-section' });
			var listFieldset = E('fieldset', { 'class': 'cbi-section' });
			var listLegend = E('legend', {}, _('Conversations'));
		
		listFieldset.appendChild(listLegend);

		// Create table
		var table = E('table', { 'class': 'table cbi-section-table' });
		var thead = E('thead', {}, [
			E('tr', { 'class': 'tr cbi-section-table-titles' }, [
				E('th', { 'class': 'th', 'style': 'width: 30%' }, _('Contact')),
				E('th', { 'class': 'th', 'style': 'width: 50%' }, _('Last Message')),
				E('th', { 'class': 'th', 'style': 'width: 15%' }, _('Time')),
				E('th', { 'class': 'th', 'style': 'width: 5%' }, _('Count'))
			])
		]);
		table.appendChild(thead);

		var tbody = E('tbody', {});

		// Add conversation rows
		for (var i = 0; i < conversations.length; i++) {
			var conv = conversations[i];
			var lastMsg = conv.messages && conv.messages.length > 0 ? 
			              conv.messages[conv.messages.length - 1] : null;
			
			var contact = smsService.formatPhoneNumber(conv.contact);
			var preview = lastMsg ? smsService.truncateMessage(lastMsg.content, 40) : '';
			var time = lastMsg ? smsService.formatTimestamp(lastMsg.timestamp) : '';
			var count = conv.messages ? conv.messages.length : 0;
			
			// Use unread_count from backend
			var unreadCount = conv.unread_count || 0;

			var row = E('tr', { 
				'class': 'tr cbi-section-table-row' + (unreadCount > 0 ? ' sms-unread-conversation' : ''),
				'style': 'cursor: pointer;' + (unreadCount > 0 ? ' font-weight: bold;' : ''),
				'data-contact': conv.contact
			}, [
				E('td', { 'class': 'td' }, [
					contact,
					unreadCount > 0 ? E('span', { 
						'class': 'sms-unread-badge',
						'style': 'background: #e74c3c; color: white; border-radius: 10px; padding: 2px 6px; margin-left: 8px; font-size: 11px;'
					}, String(unreadCount)) : ''
				]),
				E('td', { 'class': 'td' }, preview),
				E('td', { 'class': 'td' }, time),
				E('td', { 'class': 'td', 'style': 'text-align: center' }, String(count))
			]);

			// Add click handler
			row.addEventListener('click', L.bind(function(contact) {
				L.ui.showModal(_('Loading...'), E('div', { 'class': 'spinning' }));
				window.location.href = L.url('admin/modem/qmodem/sms/conversation', encodeURIComponent(contact));
			}, this, conv.contact));

			tbody.appendChild(row);
		}

		table.appendChild(tbody);
		listFieldset.appendChild(table);
		listDiv.appendChild(listFieldset);
		conversationsDiv.appendChild(listDiv);
		}

		// Add action buttons - always show these regardless of whether there are conversations
		var buttonDiv = E('div', { 'class': 'cbi-page-actions' });
		
		var newConversationBtn = E('button', {
			'class': 'cbi-button cbi-button-add',
			'click': L.bind(function(ev) {
				ev.preventDefault();
				this.showNewConversationDialog(configSection);
			}, this)
		}, _('New Conversation'));
		
		var refreshBtn = E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': L.bind(function(ev) {
				ev.preventDefault();
				var loading = E('div', { 'class': 'spinning' }, _('Loading...'));
				dom.content(contentArea, loading);
				this.loadSmsList(contentArea, loading, configSection);
			}, this)
		}, _('Refresh'));
		
		buttonDiv.appendChild(newConversationBtn);
		buttonDiv.appendChild(refreshBtn);
		conversationsDiv.appendChild(buttonDiv);

		contentArea.appendChild(conversationsDiv);
	},

	showNewConversationDialog: function(configSection) {
		var self = this;
		
		var modalContent = E('div', { 'class': 'cbi-section' }, [
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Phone Number')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('input', {
						'type': 'text',
						'id': 'new-conversation-phone',
						'class': 'cbi-input-text',
						'placeholder': _('Enter phone number')
					})
				])
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Message')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('textarea', {
						'id': 'new-conversation-message',
						'class': 'cbi-input-textarea',
						'rows': '4',
						'placeholder': _('Enter your message here...')
					})
				])
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Encoding')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('select', {
						'id': 'new-conversation-encoding',
						'class': 'cbi-input-select'
					}, [
						E('option', { 'value': '7bit' }, _('7-bit (ASCII)')),
						E('option', { 'value': '16bit', 'selected': 'selected' }, _('16-bit (Unicode)'))
					])
				])
			]),
			E('div', { 
				'class': 'cbi-value',
				'style': 'font-size: 12px; color: #666;'
			}, [
				E('label', { 'class': 'cbi-value-title' }, _('Length')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('span', { 'id': 'new-conversation-counter' }, '0/160')
				])
			])
		]);

		// Show modal first
		ui.showModal(_('New Conversation'), [
			modalContent,
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'click': function() {
						ui.hideModal();
					}
				}, _('Cancel')),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-save',
					'id': 'new-conversation-send-btn',
					'click': function() {
						var phoneInput = document.getElementById('new-conversation-phone');
						var messageInput = document.getElementById('new-conversation-message');
						var encodingInput = document.getElementById('new-conversation-encoding');
						
						var phone = phoneInput.value.trim();
						var message = messageInput.value.trim();
						var encoding = encodingInput.value;

						if (!phone) {
							ui.addNotification(null, E('p', _('Please enter a phone number')), 'error');
							return;
						}

						if (!message) {
							ui.addNotification(null, E('p', _('Please enter a message')), 'error');
							return;
						}

						// Close modal and send message
						ui.hideModal();
						
						ui.showModal(_('Sending...'), E('div', { 'class': 'spinning' }, _('Sending message...')));

						smsService.sendSms(configSection, phone, message, encoding).then(function(result) {
							ui.hideModal();
							
							if (result.error) {
								ui.addNotification(null, E('p', _('Failed to send SMS: ') + result.error), 'error');
								return;
							}

							if (result.success) {
								ui.addNotification(null, E('p', _('Message sent successfully')), 'info');
								// Navigate to the conversation
								setTimeout(function() {
									window.location.href = L.url('admin/modem/qmodem/sms/conversation', encodeURIComponent(phone));
								}, 500);
							}
						}).catch(function(err) {
							ui.hideModal();
							ui.addNotification(null, E('p', _('Failed to send SMS: ') + err.message), 'error');
						});
					}
				}, _('Send'))
			])
		]);

		// Add character counter
		var textarea = document.getElementById('new-conversation-message');
		var encodingSelect = document.getElementById('new-conversation-encoding');
		var counter = document.getElementById('new-conversation-counter');

		var updateCounter = function() {
			var text = textarea.value;
			var encoding = encodingSelect.value;
			var maxLength = encoding === '7bit' ? 160 : 70;
			var parts = Math.ceil(text.length / maxLength);
			
			if (parts > 1) {
				maxLength = encoding === '7bit' ? 153 : 66;
				parts = Math.ceil(text.length / maxLength);
			}
			
			counter.textContent = text.length + ' / ' + maxLength + 
			                      (parts > 1 ? ' (' + parts + ' parts)' : '');
			
			if (text.length > maxLength * 5) {
				counter.style.color = 'red';
			} else if (parts > 1) {
				counter.style.color = 'orange';
			} else {
				counter.style.color = '#666';
			}
		};

	textarea.addEventListener('input', updateCounter);
	encodingSelect.addEventListener('change', updateCounter);
},

loadUciConfig: function(configSection, smsDbPathInput, smsAutoDeleteCheckbox) {
	return uci.load('qmodem').then(function() {
		// Load sms_db_path
		var dbPath = uci.get('qmodem', configSection, 'sms_db_path');
		if (dbPath) {
			smsDbPathInput.value = dbPath;
		} else {
			smsDbPathInput.value = '';
		}

		// Load sms_auto_delete_from_sim
		var autoDelete = uci.get('qmodem', configSection, 'sms_auto_delete_from_sim');
		smsAutoDeleteCheckbox.checked = (autoDelete === '1');
	});
},

saveUciOption: function(configSection, option, value) {
	return uci.load('qmodem').then(function() {
		uci.set('qmodem', configSection, option, value);
		return uci.save();
	}).then(function() {
		ui.addNotification(null, E('p', _('Configuration saved')), 'info');
	}).catch(function(err) {
		ui.addNotification(null, E('p', _('Failed to save configuration: ') + err.message), 'error');
	});
},

loadSmsStorage: function(configSection, readingSelect, writingSelect, etcSelect) {
	var self = this;
	
	// Reset to Loading state
	readingSelect.value = 'Loading';
	writingSelect.value = 'Loading';
	etcSelect.value = 'Loading';
	
	return smsService.getSmsStorage(configSection).then(function(result) {
		if (result.error) {
			console.error('Failed to get SMS storage:', result.error);
			ui.addNotification(null, E('p', _('Failed to get SMS storage: ') + result.error), 'error');
			return;
		}
		
		if (!result.storage) {
			console.error('No storage info returned');
			return;
		}
		
		var storage = result.storage;
		
		// Update select values with current storage
		if (storage.mem1) {
			readingSelect.value = storage.mem1;
		}
		if (storage.mem2) {
			writingSelect.value = storage.mem2;
		}
		if (storage.mem3) {
			etcSelect.value = storage.mem3;
		}
		
		// Update option labels with usage info
		var meText = _('Mobile Equipment (ME)');
		var smText = _('SIM Card (SM)');
		
		if (storage.ME && storage.ME.total > 0) {
			meText += ' (' + storage.ME.used + '/' + storage.ME.total + ')';
		}
		
		if (storage.SM && storage.SM.total > 0) {
			smText += ' (' + storage.SM.used + '/' + storage.SM.total + ')';
		}
		
		// Update all selects
		[readingSelect, writingSelect, etcSelect].forEach(function(select) {
			var meOption = select.querySelector('option[value="ME"]');
			var smOption = select.querySelector('option[value="SM"]');
			
			if (meOption) meOption.textContent = meText;
			if (smOption) smOption.textContent = smText;
		});
		
	}).catch(function(err) {
		console.error('Error loading SMS storage:', err);
		ui.addNotification(null, E('p', _('Error loading SMS storage: ') + err.message), 'error');
	});
},

setSmsStorage: function(configSection, readingSelect, writingSelect, etcSelect) {
	var self = this;
	
	var mem1 = readingSelect.value;
	var mem2 = writingSelect.value;
	var mem3 = etcSelect.value;
	
	if (mem1 === 'Loading' || mem2 === 'Loading') {
		ui.addNotification(null, E('p', _('Please wait for storage info to load')), 'warning');
		return;
	}
	
	ui.showModal(_('Setting SMS Storage'), E('div', { 'class': 'spinning' }, _('Applying settings...')));
	
	return smsService.setSmsStorage(configSection, mem1, mem2, mem3).then(function(result) {
		ui.hideModal();
		
		if (result.error) {
			ui.addNotification(null, E('p', _('Failed to set SMS storage: ') + result.error), 'error');
			return;
		}
		
		if (result.success) {
			ui.addNotification(null, E('p', _('SMS storage settings applied successfully')), 'info');
			// Reload storage info to verify
			self.loadSmsStorage(configSection, readingSelect, writingSelect, etcSelect);
		} else {
			ui.addNotification(null, E('p', _('Failed to set SMS storage')), 'error');
		}
	}).catch(function(err) {
		ui.hideModal();
		ui.addNotification(null, E('p', _('Error setting SMS storage: ') + err.message), 'error');
	});
},

handleSaveApply: null,
handleSave: null,
handleReset: null
});
