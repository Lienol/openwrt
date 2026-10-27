'use strict';
'require baseclass';
'require qmodem.qmodem as qmodem';

function progressbar(value, max, min, unit) {
	var val = parseInt(value) || 0,
		maximum = parseInt(max) || 100,
		minimum = parseInt(min) || 0,
		unit = unit || '',
		pc = Math.floor((100 / (maximum - minimum)) * (val - minimum));

	return E('div', {
		'class': 'cbi-progressbar',
		'title': '%s / %s%s (%d%%)'.format(val, maximum, unit, pc)
	}, E('div', { 'style': 'width:%.2f%%'.format(pc) }));
}

return baseclass.extend({
	title: _('Modem Info'),

	load: function() {
		return qmodem.getModemSections().then(function(sections) {
			var promises = sections.map(function(section) {
				return Promise.all([
					qmodem.getBaseInfo(section.id),
					qmodem.getCellInfo(section.id)
				]).then(function(results) {
					var allInfo = [];
					if (results[0] && results[0].modem_info) {
						allInfo = allInfo.concat(results[0].modem_info);
					}
					if (results[1] && results[1].modem_info) {
						allInfo = allInfo.concat(results[1].modem_info);
					}
					return {
						section: section,
						info: allInfo
					};
				});
			});
			return Promise.all(promises);
		});
	},

	render: function(data) {
		var container = E('div', {});

		if (!data || data.length === 0) {
			var table = E('table', { 'class': 'table' });
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '100%' }, [ _('No modem information available') ])
			]));
			return table;
		}

		try {
			for (var m = 0; m < data.length; m++) {
				var modem = data[m];
				var table = E('table', { 'class': 'table' });
				var fields = [];

				// Add section header
				if (modem.section && modem.section.name) {
					table.appendChild(E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th', 'colspan': '2' }, [ modem.section.name ])
					]));
				}

				var infoArray = modem.info || [];
				for (var i = 0; i < infoArray.length; i++) {
					var entry = infoArray[i];
					var full_name = entry.full_name;
					var extra_info = entry.extra_info;
					
					if (entry.value == null) {
						continue;
					}
					
					if ((entry.class == 'Base Information') || 
						(entry.class == 'Cell Information' && entry.type == 'progress_bar')) {
						fields.push(extra_info ? '%s (%s)'.format(_(full_name), extra_info) : _(full_name));
						fields.push(entry);
					}
				}

				if (fields.length == 0) {
					table.appendChild(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '100%' }, [ _('No modem information available') ])
					]));
					container.appendChild(table);
					continue;
				}

				for (var i = 0; i < fields.length; i += 2) {
					var entry = fields[i + 1];
					var type = entry.type;
					var value;
					if (type == 'progress_bar') {
						value = E('td', { 'class': 'td left' }, [
							(entry.value != null) ? progressbar(entry.value, entry.max_value, entry.min_value, entry.unit) : '?'
						]);
					} else {
						value = E('td', { 'class': 'td left' }, [ (entry.value != null) ? entry.value : '?' ]);
					}

					table.appendChild(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
						value
					]));
				}

				container.appendChild(table);
			}

			return container;
		}
		catch (e) {
			var table = E('table', { 'class': 'table' });
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '100%' }, [ _('No modem information available') ])
			]));
			return table;
		}
	}
});
