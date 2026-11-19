'use strict';
'require view';
'require rpc';
'require ui';

/* Tools -> IPv6: one switch for the whole IPv6 path. The backend is the
   `byte` rpcd object, so the page works on the same build that ships the BYTE
   panel - no separate provider and no /usr/sbin helper to keep in sync. */
var callMode = rpc.declare({
	object: 'byte',
	method: 'ipv6_mode',
	params: [ 'action' ],
	expect: { '': {} }
});
var callGuard = rpc.declare({
	object: 'byte',
	method: 'dns_guard',
	params: [ 'action' ],
	expect: { '': {} }
});

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callMode('status'), { ok: false }),
			L.resolveDefault(callGuard('status'), { ok: false })
		]).then(function(r) { return { mode: r[0], guard: r[1] }; });
	},

	render: function(data) {
		var status = data.mode || {}, guard = data.guard || {};
		var st = {
			mode: (status && status.ok) ? status.mode : null,
			active: !!(status && status.ok && status.active),
			uplink: !!(status && status.ok && status.uplink)
		};

		var stateEl = E('strong', {}, [ _('Reading…') ]);
		var detailEl = E('p', { 'class': 'cbi-section-descr' });
		var msgEl = E('p', { 'class': 'cbi-section-descr' });
		var btn = E('button', { 'type': 'button', 'class': 'cbi-button cbi-button-apply' });

		function paint() {
			var on = st.mode === 'on';

			if (st.mode == null)
				stateEl.textContent = _('Unknown');
			else
				stateEl.textContent = on ? _('Enabled') : _('Disabled');

			if (on && !st.uplink)
				detailEl.textContent = _('Enabled, but the uplink has no IPv6 address yet: the carrier may not offer one, or the modem is still redialing.');
			else if (on)
				detailEl.textContent = _('Clients get IPv6 addresses and AAAA records. The LAN announces a prefix through router advertisements and DHCPv6.');
			else if (st.uplink)
				detailEl.textContent = _('IPv6 is off for clients, but the uplink still holds an IPv6 address. It disappears when the modem redials.');
			else
				detailEl.textContent = _('IPv4 only. Clients get no IPv6 address and no AAAA records; the modem dials a single-stack IPv4 context.');

			btn.textContent = on ? _('Disable IPv6') : _('Enable IPv6');
			btn.disabled = (st.mode == null);
		}

		function apply(next) {
			msgEl.textContent = _('Saving…');
			btn.disabled = true;
			return callMode(next).then(function(res) {
				btn.disabled = false;
				if (!res || res.ok !== true) {
					paint();
					msgEl.textContent = (res && res.message) || _('The change was not applied.');
					return;
				}
				st.mode = res.mode || next;
				st.active = !!res.active;
				st.uplink = !!res.uplink;
				paint();
				msgEl.textContent = res.changed
					? _('Saved. The modem redials in the background; IPv4 drops for a few seconds.')
					: _('Already in that state; nothing changed.');
				ui.addNotification(null, E('p', {}, [
					next === 'on'
						? _('IPv6 enabled. Clients start using it once the carrier delegates a usable prefix.')
						: _('IPv6 disabled. Clients no longer get IPv6 addresses or AAAA records.')
				]), 'info');
			}).catch(function(err) {
				btn.disabled = false;
				paint();
				msgEl.textContent = String(err);
			});
		}

		btn.addEventListener('click', function() {
			var next = st.mode === 'on' ? 'off' : 'on';

			return ui.showModal(next === 'on'
				? _('Enable IPv6?')
				: _('Disable IPv6?'), [
				E('p', {}, [ next === 'on'
					? _('The modem redials with a dual-stack PDP context, the LAN starts announcing a prefix, and dnsmasq returns AAAA records again.')
					: _('The modem redials with an IPv4-only PDP context, the LAN stops announcing a prefix, and dnsmasq filters AAAA answers.') ]),
				E('p', { 'class': 'cbi-section-descr' }, [ _('IPv4 keeps working, but the uplink drops for about 10-30 seconds while the modem redials.') ]),
				E('p', { 'class': 'cbi-section-descr' }, [ _('Known limitation on the current carrier: the delegated IPv6 prefix is not routed, so browsers that try an unreachable AAAA address load pages slowly. Enable IPv6 only if your uplink really routes it.') ]),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn',
						'click': ui.hideModal
					}, [ _('Cancel') ]),
					' ',
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function() {
							ui.hideModal();
							return apply(next);
						}
					}, [ next === 'on' ? _('Enable IPv6') : _('Disable IPv6') ])
				])
			]);
		});

		paint();

		var guardSwitch = E('input', { 'type': 'checkbox', 'class': 'cbi-input-checkbox', 'checked': (guard && guard.guard) ? 'checked' : null });
		var guardMsg = E('p', { 'class': 'cbi-section-descr' });
		guardSwitch.addEventListener('change', function() {
			guardSwitch.disabled = true;
			callGuard(guardSwitch.checked ? 'on' : 'off').then(function(r) {
				guardSwitch.disabled = false;
				guardMsg.textContent = (r && r.ok) ? (r.guard ? _('Bypass blocking is on.') : _('Bypass blocking is off.')) : _('Failed to apply.');
			});
		});
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ _('IPv6 uplink') ]),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, [ _('State: '), stateEl ]),
				detailEl,
				E('div', { 'class': 'cbi-section-node' }, [ btn ]),
				msgEl,
				E('p', { 'class': 'cbi-section-descr' }, [
					_('One switch for the whole path: the modem PDP type, the LAN router advertisements and DHCPv6, and dnsmasq AAAA filtering. The IPv6 stack itself is never removed from the kernel.')
				])
			]),
			E('h2', {}, [ _('DNS bypass guard') ]),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, [ _('Blocks LAN clients that try to skip this router: DNS-over-TLS (853) and QUIC (UDP 443). With it on, Android Private DNS and similar clients must fall back to the router or lose resolution.') ]),
				E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, [ _('Block bypass') ]), E('div', { 'class': 'cbi-value-field' }, [ guardSwitch ]) ]),
				E('p', { 'class': 'cbi-section-descr' }, [ _('This cannot block DNS tunnelled inside ordinary HTTPS on 443; that would require breaking TLS. It does stop Private DNS, DoT clients and QUIC-based bypass.') ]),
				guardMsg
			])
		]);
	}
});
