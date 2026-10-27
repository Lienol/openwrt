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
		// Get contact from URL hash or path
		var hash = window.location.hash || window.location.pathname;
		var match = hash.match(/\/conversation\/([^\/\?#]+)/);
		var contact = match ? decodeURIComponent(match[1]) : null;

		return Promise.all([
			qmodem.getModemSections(),
			Promise.resolve(contact)
		]);
	},

	render: function(loadResult) {
		var self = this;
		var modems = loadResult[0];
		var contact = loadResult[1];

		if (!contact) {
			return E('div', { 'class': 'cbi-map' }, [
				E('h2', {}, _('SMS Conversation')),
				E('div', { 'class': 'alert-message error' }, 
					_('Invalid contact'))
			]);
		}

		// Filter enabled modems
		modems = modems.filter(function(m) { return m.enabled; });

		if (modems.length === 0) {
			return E('div', { 'class': 'alert-message warning' }, 
				_('No modems configured or all modems are disabled.'));
		}

		var container = E('div', { 'class': 'cbi-map' });

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

		selectorTable.appendChild(selectorBody);
		selectorSection.appendChild(selectorTable);
		container.appendChild(selectorSection);

		// Header with back button
		var headerDiv = E('div', { 'class': 'sms-conversation-header' }, [
			E('button', {
				'class': 'cbi-button cbi-button-neutral',
				'style': 'margin-right: 10px;',
				'click': function(ev) {
					ev.preventDefault();
					window.location.href = L.url('admin/modem/qmodem/sms');
				}
			}, '← ' + _('Back')),
			E('h2', { 'style': 'display: inline-block; margin: 0;' }, 
				_('Conversation with ') + smsService.formatPhoneNumber(contact))
		]);
		container.appendChild(headerDiv);

		// Messages area
		var messagesArea = E('div', { 
			'id': 'sms-messages-area',
			'class': 'sms-messages-area',
			'style': 'margin-top: 20px;'
		});
		container.appendChild(messagesArea);

		// Loading indicator
		var loadingDiv = E('div', { 'class': 'spinning' }, _('Loading messages...'));
		messagesArea.appendChild(loadingDiv);

		// Get selected modem
		var selectedModem = select.value;

		// Reply form
		var replyForm = this.createReplyForm(contact, selectedModem, messagesArea, loadingDiv, select);
		container.appendChild(replyForm);

		// Load conversation
		this.loadConversation(messagesArea, loadingDiv, selectedModem, contact);

		// Selector change handler
		select.addEventListener('change', function() {
			var loading = E('div', { 'class': 'spinning' }, _('Loading...'));
			dom.content(messagesArea, loading);
			self.loadConversation(messagesArea, loading, select.value, contact);
		});

		// Timezone checkbox change handler for received messages
		timezoneReceivedCheckbox.addEventListener('change', function() {
			self.setUtcOffsetSetting('received', timezoneReceivedCheckbox.checked);
			var loading = E('div', { 'class': 'spinning' }, _('Loading...'));
			dom.content(messagesArea, loading);
			self.loadConversation(messagesArea, loading, select.value, contact);
		});

		// Timezone checkbox change handler for sent messages
		timezoneSentCheckbox.addEventListener('change', function() {
			self.setUtcOffsetSetting('sent', timezoneSentCheckbox.checked);
			var loading = E('div', { 'class': 'spinning' }, _('Loading...'));
			dom.content(messagesArea, loading);
			self.loadConversation(messagesArea, loading, select.value, contact);
		});

		// Start polling for new messages
		poll.add(function() {
			self.pollConversation(messagesArea, select.value, contact);
		}, 5);

		return container;
	},

	createReplyForm: function(contact, configSection, messagesArea, loadingDiv, select) {
		var self = this;

		var formDiv = E('div', { 
			'class': 'cbi-section',
			'style': 'margin-top: 20px;'
		});

		var fieldset = E('fieldset', { 'class': 'cbi-section' });
		var legend = E('legend', {}, _('Send Message'));
		fieldset.appendChild(legend);

		// Message input
		var inputDiv = E('div', { 'class': 'cbi-value' });
		var inputLabel = E('label', { 'class': 'cbi-value-title' }, _('Message'));
		var inputField = E('div', { 'class': 'cbi-value-field' });
		var textarea = E('textarea', {
			'id': 'sms-reply-text',
			'class': 'cbi-input-textarea',
			'rows': '3',
			'placeholder': _('Enter your message here...')
		});
		inputField.appendChild(textarea);
		inputDiv.appendChild(inputLabel);
		inputDiv.appendChild(inputField);
		fieldset.appendChild(inputDiv);

		// Encoding selection
		var encodingDiv = E('div', { 'class': 'cbi-value' });
		var encodingLabel = E('label', { 'class': 'cbi-value-title' }, _('Encoding'));
		var encodingField = E('div', { 'class': 'cbi-value-field' });
		var encodingSelect = E('select', {
			'id': 'sms-encoding',
			'class': 'cbi-input-select'
		}, [
			E('option', { 'value': '7bit' }, _('7-bit (ASCII)')),
			E('option', { 'value': '16bit', 'selected': 'selected' }, _('16-bit (Unicode)'))
		]);
		encodingField.appendChild(encodingSelect);
		encodingDiv.appendChild(encodingLabel);
		encodingDiv.appendChild(encodingField);
		fieldset.appendChild(encodingDiv);

		// Character counter
		var counterDiv = E('div', { 
			'class': 'cbi-value',
			'style': 'font-size: 12px; color: #666;'
		});
		var counter = E('span', { 'id': 'sms-char-counter' }, '0/160');
		counterDiv.appendChild(E('label', { 'class': 'cbi-value-title' }, _('Length')));
		counterDiv.appendChild(E('div', { 'class': 'cbi-value-field' }, counter));
		fieldset.appendChild(counterDiv);

		// Update character counter
		textarea.addEventListener('input', function() {
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
		});

		// Buttons
		var buttonsDiv = E('div', { 'class': 'cbi-page-actions' });
		var sendBtn = E('button', {
			'class': 'cbi-button cbi-button-save',
			'click': function(ev) {
				ev.preventDefault();
				var currentModem = select ? select.value : configSection;
				self.sendMessage(textarea, encodingSelect, contact, currentModem, 
				                messagesArea, loadingDiv, sendBtn, select);
			}
		}, _('Send'));
		
		var clearBtn = E('button', {
			'class': 'cbi-button cbi-button-reset',
			'click': function(ev) {
				ev.preventDefault();
				textarea.value = '';
				textarea.dispatchEvent(new Event('input'));
			}
		}, _('Clear'));

		buttonsDiv.appendChild(sendBtn);
		buttonsDiv.appendChild(clearBtn);
		fieldset.appendChild(buttonsDiv);

		formDiv.appendChild(fieldset);
		return formDiv;
	},

	sendMessage: function(textarea, encodingSelect, contact, configSection, 
	                      messagesArea, loadingDiv, sendBtn, select) {
		var self = this;
		var message = textarea.value.trim();
		var encoding = encodingSelect.value;

		if (!message) {
			ui.addNotification(null, E('p', _('Please enter a message')), 'error');
			return;
		}

		// Disable send button
		sendBtn.disabled = true;
		sendBtn.textContent = _('Sending...');

		smsService.sendSms(configSection, contact, message, encoding).then(function(result) {
			sendBtn.disabled = false;
			sendBtn.textContent = _('Send');

			if (result.error) {
				ui.addNotification(null, E('p', _('Failed to send SMS: ') + result.error), 'error');
				return;
			}

			if (result.success) {
				ui.addNotification(null, E('p', _('Message sent successfully')), 'info');
				textarea.value = '';
				textarea.dispatchEvent(new Event('input'));
				
				// Reload conversation with current modem
				var currentModem = select ? select.value : configSection;
				self.loadConversation(messagesArea, loadingDiv, currentModem, contact);
			}
		}).catch(function(err) {
			sendBtn.disabled = false;
			sendBtn.textContent = _('Send');
			ui.addNotification(null, E('p', _('Failed to send SMS: ') + err.message), 'error');
		});
	},

	loadConversation: function(messagesArea, loadingDiv, configSection, contact) {
		var self = this;

		smsService.getConversation(configSection, contact).then(function(result) {
			// Auto-mark all received messages as read
			if (result.messages && result.messages.length > 0) {
				var unreadIds = [];
				result.messages.forEach(function(msg) {
					if (msg.type === 'received' && msg.is_read === false) {
						if (msg.part_ids && msg.part_ids.length > 0) {
							// For multipart messages, mark all parts as read
							unreadIds = unreadIds.concat(msg.part_ids);
						} else {
							unreadIds.push(msg.id);
						}
					}
				});
				if (unreadIds.length > 0) {
					smsService.markRead(configSection, unreadIds);
				}
			}

			// Adjust timestamps if UTC offset is enabled (based on message type)
			if (result.messages && result.messages.length > 0) {
				var needsReSort = false;
				result.messages.forEach(function(msg) {
					if (msg.timestamp && msg.type) {
						var originalTimestamp = msg.timestamp;
						msg.timestamp = self.adjustTimestampForUtcOffset(msg.timestamp, msg.type);
						if (originalTimestamp !== msg.timestamp) {
							needsReSort = true;
						}
					}
				});
				// Re-sort messages by timestamp if any were adjusted
				if (needsReSort) {
					result.messages.sort(function(a, b) {
						return a.timestamp - b.timestamp;
					});
				}
			}

			// Remove loading indicator
			if (loadingDiv && loadingDiv.parentNode) {
				dom.content(messagesArea, null);
			}

			if (result.error) {
				messagesArea.appendChild(E('div', { 'class': 'alert-message error' }, 
					_('Error loading messages: ') + result.error));
				return;
			}

			// Render messages
			self.renderMessages(messagesArea, result.messages || [], configSection);
		}).catch(function(err) {
			if (loadingDiv && loadingDiv.parentNode) {
				dom.content(messagesArea, null);
			}
			messagesArea.appendChild(E('div', { 'class': 'alert-message error' }, 
				_('Failed to load messages: ') + err.message));
		});
	},

	pollConversation: function(messagesArea, configSection, contact) {
		var self = this;
		
		smsService.getConversation(configSection, contact).then(function(result) {
			if (!result.error && result.messages) {
				// Adjust timestamps if UTC offset is enabled (based on message type)
				if (result.messages.length > 0) {
					var needsReSort = false;
					result.messages.forEach(function(msg) {
						if (msg.timestamp && msg.type) {
							var originalTimestamp = msg.timestamp;
							msg.timestamp = self.adjustTimestampForUtcOffset(msg.timestamp, msg.type);
							if (originalTimestamp !== msg.timestamp) {
								needsReSort = true;
							}
						}
					});
					// Re-sort messages by timestamp if any were adjusted
					if (needsReSort) {
						result.messages.sort(function(a, b) {
							return a.timestamp - b.timestamp;
						});
					}
				}
				self.renderMessages(messagesArea, result.messages, configSection);
			}
		}).catch(function(err) {
			console.error('Poll error:', err);
		});
	},

	renderMessages: function(messagesArea, messages, configSection) {
		var self = this;

		// Clear content
		dom.content(messagesArea, null);

		if (!messages || messages.length === 0) {
			messagesArea.appendChild(E('div', { 'class': 'alert-message info' }, 
				_('No messages in this conversation')));
			return;
		}

		// Create messages list
		var messagesDiv = E('div', { 'class': 'sms-messages-list' });

		for (var i = 0; i < messages.length; i++) {
			var msg = messages[i];
			var isReceived = msg.type === 'received';
			var isSent = msg.type === 'sent';

			// Message bubble
			var bubbleClass = 'sms-message-bubble ' + 
			                  (isReceived ? 'sms-message-received' : 'sms-message-sent');
			
			var bubble = E('div', { 'class': bubbleClass });

			// Message content
			var contentDiv = E('div', { 'class': 'sms-message-content' }, msg.content);
			bubble.appendChild(contentDiv);

			// Message metadata
			var metaDiv = E('div', { 'class': 'sms-message-meta' });
			
			var timeStr = this.formatFullTimestamp(msg.timestamp);
			var timeSpan = E('span', { 'class': 'sms-message-time' }, timeStr);
			metaDiv.appendChild(timeSpan);

			// Show multipart info if applicable
			if (msg.multipart) {
				var multipartSpan = E('span', { 
					'class': 'sms-message-info',
					'style': 'margin-left: 10px;'
				}, _('Multi-part'));
				metaDiv.appendChild(multipartSpan);
			}

			// Show incomplete warning
			if (msg.incomplete) {
				var incompleteSpan = E('span', { 
					'class': 'sms-message-warning',
					'style': 'margin-left: 10px; color: orange;'
				}, _('Incomplete (part ') + msg.part + '/' + msg.total + ')');
				metaDiv.appendChild(incompleteSpan);
			}

			// Show failed indicator for sent messages
			if (isSent && msg.is_success === false) {
				var failedSpan = E('span', { 
					'class': 'sms-message-failed',
					'style': 'margin-left: 10px; color: #e74c3c;',
					'title': _('Failed to send')
				}, '✗ ' + _('Failed'));
				metaDiv.appendChild(failedSpan);
			}

			// Delete button for all messages
			var deleteBtn = E('button', {
				'class': 'cbi-button cbi-button-remove',
				'style': 'margin-left: 10px; font-size: 11px; padding: 2px 6px;',
				'click': L.bind(function(message, contact, ev) {
					ev.preventDefault();
					if (confirm(_('Delete this message?'))) {
						var msgContact = message.type === 'received' ? message.sender : message.recipient;
						this.deleteMessage(configSection, message, msgContact, messagesArea);
					}
				}, this, msg, (isReceived ? msg.sender : msg.recipient))
			}, _('Delete'));
			metaDiv.appendChild(deleteBtn);

			bubble.appendChild(metaDiv);

			// Wrapper for alignment
			var wrapperClass = 'sms-message-wrapper ' + 
			                   (isReceived ? 'sms-message-wrapper-left' : 'sms-message-wrapper-right');
			var wrapper = E('div', { 'class': wrapperClass }, bubble);

			messagesDiv.appendChild(wrapper);
		}

		messagesArea.appendChild(messagesDiv);

		// Scroll to bottom
		setTimeout(function() {
			messagesArea.scrollTop = messagesArea.scrollHeight;
		}, 100);
	},

	deleteMessage: function(configSection, message, contact, messagesArea) {
		var self = this;

		// Determine which IDs to delete
		var idsToDelete;
		if (message.part_ids && message.part_ids.length > 0) {
			// For multipart messages, delete all parts
			idsToDelete = message.part_ids;
		} else {
			// For single messages, delete by ID
			idsToDelete = [message.id];
		}

		smsService.deleteSms(
			configSection,
			message.type,
			idsToDelete
		).then(function(result) {
			if (result.error) {
				ui.addNotification(null, E('p', _('Failed to delete SMS: ') + result.error), 'error');
				return;
			}

			ui.addNotification(null, E('p', _('Message deleted')), 'info');
			
			// Reload conversation
			var loading = E('div', { 'class': 'spinning' }, _('Loading...'));
			dom.content(messagesArea, loading);
			self.loadConversation(messagesArea, loading, configSection, contact);
		}).catch(function(err) {
			ui.addNotification(null, E('p', _('Failed to delete SMS: ') + err.message), 'error');
		});
	},

	formatFullTimestamp: function(timestamp) {
		var date = new Date(timestamp * 1000);
		
		return String(date.getFullYear()) + '-' + 
		       String(date.getMonth() + 1).padStart(2, '0') + '-' + 
		       String(date.getDate()).padStart(2, '0') + ' ' +
		       String(date.getHours()).padStart(2, '0') + ':' + 
		       String(date.getMinutes()).padStart(2, '0') + ':' + 
		       String(date.getSeconds()).padStart(2, '0');
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
