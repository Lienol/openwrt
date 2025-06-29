'use strict';
'require baseclass';
'require rpc';

var callModemInfo = rpc.declare({
	object: 'modem_ctrl',
	method: 'info'
});

function progressbar(value, max, min, unit) {
	var value = parseInt(value) || 0,
		max = parseInt(max) || 100,
		min = parseInt(min) || 0,
		unit = unit || '',
		pc = Math.floor((100 / (max - min)) * (value - min));

	return E('div', {
		'class': 'cbi-progressbar',
		'title': '%s / %s%s (%d%%)'.format(value, max, unit,pc)
	}, E('div', { 'style': 'width:%.2f%%'.format(pc) }));
}


return baseclass.extend({
	title: _('Modem Info'),

	load: function() {
		return Promise.all([
			L.resolveDefault(callModemInfo(), {}),
		]);
	},

	render: function(data) {
		
		var table = E('table', { 'class': 'table' });
		try {
			var infos   = data[0].info
			var fields = [];
			for (let modem_info of infos) {
				var info = modem_info.modem_info;
				
				for (var entry of info) {
					var full_name = entry.full_name;
					var extra_info = entry.extra_info;
					if (entry.value == null) {
						continue
					}
					if ((entry.class == 'Base Information') ||(entry.class == '"SIM Information"')  || (entry.class == 'Cell Information' && entry.type == 'progress_bar')) {
					fields.push(extra_info ? '%s (%s)'.format(_(full_name), extra_info) : _(full_name));
					fields.push(entry);
					}
				}
				
				if (fields.length == 0) {
					table.appendChild(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '100%' }, [ _('No modem information available') ])
					]));
					return table;
				}
			}
	
			
	
			for (var i = 0; i < fields.length; i += 2) {
				let entry, type, value;
				entry = fields[i + 1];
				type = entry.type;
				if (type == 'progress_bar') {
					value = E('td', { 'class': 'td left' }, [
						(entry.value != null) ? progressbar(entry.value, entry.max_value, entry.min_value, entry.unit) : '?'
					])
				} else {
					value = E('td', { 'class': 'td left' }, [ (fields[i + 1] != null) ? entry.value : '?' ])
				}
	
				table.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
					value
				]));
			}
	
			return table;
		}
		catch (e) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '100%' }, [ _('No modem information available') ])
			]));
			return table;
			}
			
		
	}
});
