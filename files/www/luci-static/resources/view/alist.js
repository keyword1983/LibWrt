'use strict';
'require view';
'require uci';
'require form';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('alist', _('AList'), _('AList 是支持多種存儲的檔案列表程式。'));

		s = m.section(form.NamedSection, 'config', 'alist', _('全域設定'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('啟用 AList 服務'));
		o.rmempty = false;

		o = s.option(form.Value, 'port', _('埠號 (Port)'));
		o.datatype = 'port';
		o.default = '5244';

		o = s.option(form.Button, '_open', _('開啟 AList Web 介面'));
		o.inputtitle = _('開啟 AList 控制台網頁 (Port 5244)');
		o.inputstyle = 'apply';
		o.onclick = function() {
			window.open('http://' + window.location.hostname + ':5244', '_blank');
		};

		return m.render();
	}
});
