(function () {
  const APP_CONFIG = Object.freeze({
    supabaseUrl:
      (window.__APP_CONFIG__ && window.__APP_CONFIG__.supabaseUrl) ||
      'https://nksszbvoiqarfjlrfmor.supabase.co',
    supabaseAnonKey:
      (window.__APP_CONFIG__ && window.__APP_CONFIG__.supabaseAnonKey) ||
      'sb_publishable_f97pAya_2yZoySsTh3uuIg_CeyqiyC-',
    createPaymentEndpoint:
      (window.__APP_CONFIG__ && window.__APP_CONFIG__.createPaymentEndpoint) || '/api/create-payment',
    paymentStatusEndpoint:
      (window.__APP_CONFIG__ && window.__APP_CONFIG__.paymentStatusEndpoint) || '/api/payment-status',
  });

  const publicHeaders = {
    apikey: APP_CONFIG.supabaseAnonKey,
    'Content-Type': 'application/json',
  };

  if (!String(APP_CONFIG.supabaseAnonKey).startsWith('sb_')) {
    publicHeaders.Authorization = `Bearer ${APP_CONFIG.supabaseAnonKey}`;
  }

  function formatIsoTime(value) {
    if (!value) return '—';
    const date = new Date(value);
    return Number.isNaN(date.getTime())
      ? '—'
      : date.toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' });
  }

  function formatIsoDate(value) {
    if (!value) return '—';
    const date = new Date(value);
    return Number.isNaN(date.getTime())
      ? '—'
      : date.toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit', year: 'numeric' });
  }

  function localRewardFor(participantId) {
    try {
      const raw = localStorage.getItem(`raffle_local_reward_${participantId}`);
      return raw ? JSON.parse(raw) : null;
    } catch (_) {
      return null;
    }
  }

  function toParticipant(row) {
    return {
      id: row.id,
      name: row.display_name,
      chances: Number(row.chances_bought || 0),
      bonusChances: Number(row.bonus_chances || 0),
      totalChances: Number(row.total_chances || row.chances_bought || 0),
      time: formatIsoTime(row.registered_at),
      date: formatIsoDate(row.registered_at),
      province: row.province,
      city: row.city,
      photo: row.photo_url || null,
      msg: row.message || '',
      isWinner: !!row.is_winner,
    };
  }

  async function supabaseRpc(fnName, body) {
    const response = await fetch(`${APP_CONFIG.supabaseUrl}/rest/v1/rpc/${fnName}`, {
      method: 'POST',
      headers: publicHeaders,
      body: JSON.stringify(body || {}),
    });

    if (!response.ok) {
      throw new Error(await response.text());
    }

    return response.json();
  }

  async function supabaseSelect(path) {
    const response = await fetch(`${APP_CONFIG.supabaseUrl}/rest/v1/${path}`, {
      headers: publicHeaders,
    });

    if (!response.ok) {
      throw new Error(await response.text());
    }

    return response.json();
  }

  async function hydratePackages() {
    const packages = await supabaseSelect('packages?select=id,label,chances,price,badge,sort_order&is_active=eq.true&order=sort_order.asc');
    const cards = document.querySelectorAll('.pkg');

    packages.forEach((pkg, index) => {
      const card = cards[index];
      if (!card) return;
      const title = card.querySelector('.pkg-n');
      const price = card.querySelector('.pkg-price');
      if (title) {
        title.innerHTML = `${pkg.chances} <small>chance${pkg.chances > 1 ? 's' : ''}</small>`;
      }
      if (price) {
        price.textContent = `$${fmt(pkg.price)}`;
      }
      card.dataset.packageId = String(pkg.id);
    });
  }

  async function hydrateRaffleState() {
    const activeEditionRows = await supabaseRpc('public_get_active_edition');
    const activeEdition = Array.isArray(activeEditionRows) ? activeEditionRows[0] : activeEditionRows;

    if (!activeEdition || !activeEdition.edition_id) {
      toast('No hay una edición activa publicada en Supabase.');
      return;
    }

    edition = activeEdition.edition_number;
    totalChances = Number(activeEdition.chances_sold || 0);

    const publicParticipants = await supabaseRpc('public_list_participants', {
      p_edition_id: activeEdition.edition_id,
    });

    participants = (publicParticipants || []).map(toParticipant).reverse();
    updateUI();

    if (activeEdition.status === 'drawing') {
      document.getElementById('formSection').style.display = 'none';
      document.getElementById('fullNotice').style.display = 'block';
    }
  }

  async function refreshAfterPayment(participantId) {
    let attempts = 0;

    while (attempts < 5) {
      attempts += 1;
      const response = await fetch(
        `${APP_CONFIG.paymentStatusEndpoint}?participant_id=${encodeURIComponent(participantId)}`
      );
      const payload = await response.json();

      if (payload.paymentStatus === 'confirmed') {
        await hydrateRaffleState();
        toast(`Pago confirmado para ${payload.displayName || 'tu inscripción'}.`);
        return;
      }

      await new Promise((resolve) => setTimeout(resolve, 2000));
    }

    toast('Recibimos tu regreso desde Galiopay. La confirmación puede tardar unos segundos.');
  }

  function replacePaymentBadges() {
    document.querySelectorAll('.pm').forEach((node) => {
      if (node.textContent.includes('Mercado Pago')) {
        node.textContent = '💳 Galiopay';
      }
    });
    const submitButton = document.getElementById('subBtn');
    if (submitButton) {
      submitButton.textContent = '💳 IR A PAGAR AHORA';
    }
  }

  function selectedPackageId() {
    const selectedCard = document.querySelector('.pkg.sel');
    if (selectedCard && selectedCard.dataset.packageId) {
      return Number(selectedCard.dataset.packageId);
    }
    return selPkgIdx === null ? null : selPkgIdx + 1;
  }

  const originalSubmit = window.submitForm;
  window.submitForm = async function submitFormProduction() {
    if (typeof originalSubmit !== 'function') return;

    const packageId = selectedPackageId();
    const button = document.getElementById('subBtn');

    if (!packageId) {
      toast('Elegí un pack antes de continuar.');
      return;
    }

    const payload = {
      packageId,
      firstName: document.getElementById('fN').value.trim(),
      lastName: document.getElementById('fA').value.trim(),
      whatsapp: document.getElementById('fT').value.trim(),
      province: document.getElementById('fProv').value,
      city: document.getElementById('fCity').value.trim(),
      message: document.getElementById('fMsg').value.trim(),
      photoDataUrl: currentPhotoDataUrl,
      bonusChances:
        typeof window.getCombinedSelectedBonus === 'function' ? window.getCombinedSelectedBonus() : 0,
    };

    button.disabled = true;
    button.textContent = 'Preparando checkout seguro...';

    try {
      const response = await fetch(APP_CONFIG.createPaymentEndpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });

      const result = await response.json();
      if (!response.ok) {
        throw new Error(result.details || result.error || 'No se pudo iniciar el pago');
      }

      localStorage.setItem('raffle_pending_participant_id', result.participantId);
      localStorage.setItem(
        `raffle_pending_reward_${result.participantId}`,
        JSON.stringify({
          chances: selPkgIdx !== null && PKGS[selPkgIdx] ? PKGS[selPkgIdx].chances : 0,
        })
      );
      window.location.href = result.checkoutUrl;
    } catch (error) {
      button.disabled = false;
      button.textContent = '💳 IR A PAGAR CON GALIOPAY';
      toast(error.message || 'No pudimos iniciar el pago.');
    }
  };

  async function handleReturnState() {
    const params = new URLSearchParams(window.location.search);
    const participantId =
      params.get('participant_id') || localStorage.getItem('raffle_pending_participant_id');
    const paymentState = params.get('payment');

    if (!participantId || !paymentState) return;

    if (paymentState === 'failure') {
      localStorage.removeItem('raffle_pending_participant_id');
      localStorage.removeItem(`raffle_pending_reward_${participantId}`);
      toast('El pago no se completó. Podés intentarlo nuevamente.');
      return;
    }

    await refreshAfterPayment(participantId);
    localStorage.removeItem('raffle_pending_participant_id');
    localStorage.removeItem(`raffle_pending_reward_${participantId}`);
  }

  async function initProductionMode() {
    replacePaymentBadges();
    try {
      await hydratePackages();
      await hydrateRaffleState();
      await handleReturnState();
    } catch (error) {
      console.error(error);
      toast('No pudimos sincronizar la edición en vivo. Revisá la configuración de Supabase.');
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initProductionMode, { once: true });
  } else {
    initProductionMode();
  }
})();
