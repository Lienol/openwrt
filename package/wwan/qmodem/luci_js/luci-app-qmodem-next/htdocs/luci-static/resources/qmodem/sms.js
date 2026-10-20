'use strict';
'require rpc';
'require qmodem.sms-pdu as pduParser';

var callQmodemSms = rpc.declare({
	object: 'qmodem_sms',
	method: 'list_sms',
	params: ['config_section'],
	expect: { }
});

var callGetConversation = rpc.declare({
	object: 'qmodem_sms',
	method: 'get_conversation',
	params: ['config_section', 'contact'],
	expect: { }
});

var callSendSms = rpc.declare({
	object: 'qmodem_sms',
	method: 'send_sms',
	params: ['config_section', 'recipient', 'pdu', 'content'],
	expect: { }
});

var callDeleteSms = rpc.declare({
	object: 'qmodem_sms',
	method: 'delete_sms',
	params: ['config_section', 'type', 'ids'],
	expect: { }
});

var callMarkRead = rpc.declare({
	object: 'qmodem_sms',
	method: 'mark_read',
	params: ['config_section', 'ids'],
	expect: { }
});

var callGetSentHistory = rpc.declare({
	object: 'qmodem_sms',
	method: 'get_sent_history',
	params: ['config_section'],
	expect: { }
});

var callClearSentHistory = rpc.declare({
	object: 'qmodem_sms',
	method: 'clear_sent_history',
	params: ['config_section'],
	expect: { }
});

var callGetReceivedHistory = rpc.declare({
	object: 'qmodem_sms',
	method: 'get_received_history',
	params: ['config_section'],
	expect: { }
});

var callClearReceivedHistory = rpc.declare({
	object: 'qmodem_sms',
	method: 'clear_received_history',
	params: ['config_section'],
	expect: { }
});

var callGetSmsStorage = rpc.declare({
	object: 'qmodem_sms',
	method: 'get_sms_storage',
	params: ['config_section'],
	expect: { }
});

var callSetSmsStorage = rpc.declare({
	object: 'qmodem_sms',
	method: 'set_sms_storage',
	params: ['config_section', 'mem1', 'mem2', 'mem3'],
	expect: { }
});

var callGetSimSms = rpc.declare({
	object: 'qmodem_sms',
	method: 'get_sim_sms',
	params: ['config_section'],
	expect: { }
});

var callDeleteSimSms = rpc.declare({
	object: 'qmodem_sms',
	method: 'delete_sim_sms',
	params: ['config_section', 'index'],
	expect: { }
});

return L.Class.extend({
	/**
	 * List all SMS conversations
	 * @param {string} configSection - The modem configuration section
	 * @returns {Promise} Promise resolving to conversations list
	 */
	listSms: function(configSection) {
		return callQmodemSms(configSection || 'modem_1');
	},

	/**
	 * Get conversation details with a specific contact
	 * @param {string} configSection - The modem configuration section
	 * @param {string} contact - The contact phone number
	 * @returns {Promise} Promise resolving to conversation details
	 */
	getConversation: function(configSection, contact) {
		return callGetConversation(configSection || 'modem_1', contact);
	},

	/**
	 * Send SMS message
	 * @param {string} configSection - The modem configuration section
	 * @param {string} recipient - Recipient phone number
	 * @param {string} message - Message content
	 * @param {string} encoding - Encoding type ('7bit' or '16bit')
	 * @returns {Promise} Promise resolving to send result
	 */
	sendSms: function(configSection, recipient, message, encoding) {
		// Generate PDU using sms-pdu.js
		encoding = encoding || '16bit';  // Default to 16bit for better compatibility
		
		
		try {
			var pdus = pduParser.generate({
				receiver: recipient,
				text: message,
				encoding: encoding
			});


			if (!pdus || pdus.length === 0) {
				console.error('Failed to generate PDU');
				return Promise.reject(new Error('Failed to generate PDU'));
			}

			// For multi-part messages, we need to send all parts
			// For now, we'll send the first PDU and handle multi-part in the future
			var pdu = pdus[0];

			return callSendSms(configSection || 'modem_1', recipient, pdu, message).then(function(result) {
				return result;
			}).catch(function(error) {
				console.error('SMS send error:', error);
				throw error;
			});
		} catch (e) {
			console.error('Exception in sendSms:', e);
			return Promise.reject(e);
		}
	},

	/**
	 * Delete SMS message(s) by ID
	 * @param {string} configSection - The modem configuration section
	 * @param {string} type - Message type ('received' or 'sent')
	 * @param {string|number|array} ids - Message ID(s) to delete (can be single ID or array)
	 * @returns {Promise} Promise resolving to delete result
	 */
	deleteSms: function(configSection, type, ids) {
		return callDeleteSms(
			configSection || 'modem_1',
			type,
			ids
		);
	},

	/**
	 * Mark SMS as read by ID(s)
	 * @param {string} configSection - The modem configuration section
	 * @param {string|number|array} ids - Message ID(s) to mark as read (can be single ID or array)
	 * @returns {Promise} Promise resolving to mark read result
	 */
	markRead: function(configSection, ids) {
		return callMarkRead(configSection || 'modem_1', ids);
	},

	/**
	 * Get sent SMS history
	 * @param {string} configSection - The modem configuration section
	 * @returns {Promise} Promise resolving to sent SMS history
	 */
	getSentHistory: function(configSection) {
		return callGetSentHistory(configSection || 'modem_1');
	},

	/**
	 * Clear sent SMS history
	 * @param {string} configSection - The modem configuration section
	 * @returns {Promise} Promise resolving to clear result
	 */
	clearSentHistory: function(configSection) {
		return callClearSentHistory(configSection || 'modem_1');
	},

	/**
	 * Get received SMS history
	 * @param {string} configSection - The modem configuration section
	 * @returns {Promise} Promise resolving to received SMS history
	 */
	getReceivedHistory: function(configSection) {
		return callGetReceivedHistory(configSection || 'modem_1');
	},

	/**
	 * Clear received SMS history
	 * @param {string} configSection - The modem configuration section
	 * @returns {Promise} Promise resolving to clear result
	 */
	clearReceivedHistory: function(configSection) {
		return callClearReceivedHistory(configSection || 'modem_1');
	},

	/**
	 * Format timestamp to readable string
	 * @param {number} timestamp - Unix timestamp
	 * @returns {string} Formatted date string
	 */
	formatTimestamp: function(timestamp) {
		var date = new Date(timestamp * 1000);
		var now = new Date();
		var diff = now - date;
		var days = Math.floor(diff / (1000 * 60 * 60 * 24));

		if (days === 0) {
			// Today - show time
			return String(date.getHours()).padStart(2, '0') + ':' + 
			       String(date.getMinutes()).padStart(2, '0');
		} else if (days === 1) {
			// Yesterday
			return _('Yesterday');
		} else if (days < 7) {
			// This week - show day name
			var dayNames = [_('Sunday'), _('Monday'), _('Tuesday'), _('Wednesday'), 
			                _('Thursday'), _('Friday'), _('Saturday')];
			return dayNames[date.getDay()];
		} else {
			// Older - show date
			return String(date.getFullYear()) + '-' + 
			       String(date.getMonth() + 1).padStart(2, '0') + '-' + 
			       String(date.getDate()).padStart(2, '0');
		}
	},

	/**
	 * Format phone number for display
	 * @param {string} number - Phone number
	 * @returns {string} Formatted phone number
	 */
	formatPhoneNumber: function(number) {
		if (!number) return '';
		
		// Remove non-digit characters
		var digits = number.replace(/\D/g, '');
		
		// Format based on length
		if (digits.length === 11 && digits.startsWith('1')) {
			// Chinese mobile: 138 1234 5678
			return digits.substring(0, 3) + ' ' + 
			       digits.substring(3, 7) + ' ' + 
			       digits.substring(7);
		} else if (digits.length === 5) {
			// Service numbers: 10086
			return digits;
		}
		
		// Default: return as-is
		return number;
	},

	/**
	 * Truncate message content for preview
	 * @param {string} content - Message content
	 * @param {number} maxLength - Maximum length
	 * @returns {string} Truncated content
	 */
	truncateMessage: function(content, maxLength) {
		if (!content) return '';
		
		maxLength = maxLength || 50;
		
		if (content.length <= maxLength) {
			return content;
		}
		
		return content.substring(0, maxLength) + '...';
	},

	/**
	 * Get SMS storage capabilities
	 * @param {string} configSection - The modem configuration section
	 * @returns {Promise} Promise resolving to SMS storage info
	 */
	getSmsStorage: function(configSection) {
		return callGetSmsStorage(configSection || 'modem_1');
	},

	/**
	 * Set SMS storage
	 * @param {string} configSection - The modem configuration section
	 * @param {string} mem1 - Reading storage (ME or SM)
	 * @param {string} mem2 - Writing storage (ME or SM)
	 * @param {string} mem3 - Other storage (ME or SM, optional)
	 * @returns {Promise} Promise resolving to set storage result
	 */
	setSmsStorage: function(configSection, mem1, mem2, mem3) {
		return callSetSmsStorage(
			configSection || 'modem_1',
			mem1,
			mem2,
			mem3 || ''
		);
	},

	/**
	 * Get SMS directly from SIM card
	 * @param {string} configSection - The modem configuration section
	 * @returns {Promise} Promise resolving to SIM SMS list
	 */
	getSimSms: function(configSection) {
		return callGetSimSms(configSection || 'modem_1');
	},

	/**
	 * Delete SMS from SIM card by index
	 * @param {string} configSection - The modem configuration section
	 * @param {number} index - SMS index on SIM card
	 * @returns {Promise} Promise resolving to delete result
	 */
	deleteSimSms: function(configSection, index) {
		return callDeleteSimSms(configSection || 'modem_1', index);
	}
});
