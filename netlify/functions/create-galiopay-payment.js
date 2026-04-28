const { getConfig } = require('./_lib/env');
const { createPaymentLink, extractPaymentLinkId } = require('./_lib/galiopay');
const { getJsonBody, json } = require('./_lib/http');
const { rpc, supabaseRequest, uploadProfilePhoto } = require('./_lib/supabase-rest');

function firstRow(result) {
  return Array.isArray(result) ? result[0] : result;
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  try {
    const config = getConfig();
    const body = getJsonBody(event);

    const firstName = String(body.firstName || '').trim();
    const lastName = String(body.lastName || '').trim();
    const whatsapp = String(body.whatsapp || '').replace(/\D/g, '');
    const province = String(body.province || '').trim();
    const city = String(body.city || '').trim();
    const message = String(body.message || '').trim();
    const packageId = Number(body.packageId);
    const bonusChances = Number(body.bonusChances || 0);
    const photoDataUrl = body.photoDataUrl ? String(body.photoDataUrl) : null;

    if (
      firstName.length < 2 ||
      lastName.length < 2 ||
      whatsapp.length < 8 ||
      province.length < 2 ||
      city.length < 2 ||
      !Number.isInteger(packageId)
    ) {
      return json(400, { error: 'Missing or invalid registration fields' });
    }

    const edition = firstRow(await rpc(config, 'public_get_active_edition'));
    if (!edition || !edition.edition_id) {
      return json(409, { error: 'No active edition available' });
    }

    const packages = await supabaseRequest(
      config,
      `/packages?id=eq.${packageId}&is_active=eq.true&select=id,label,chances,price`
    );
    const selectedPackage = packages[0];

    if (!selectedPackage) {
      return json(404, { error: 'Selected package not found' });
    }

    const participantId = await rpc(config, 'register_participant', {
      p_edition_id: edition.edition_id,
      p_package_id: packageId,
      p_first_name: firstName,
      p_last_name_init: lastName,
      p_whatsapp: whatsapp,
      p_province: province,
      p_city: city,
      p_message: message || null,
      p_photo_url: null,
      p_bonus_chances: Math.max(0, bonusChances),
      p_payment_method: 'galiopay',
    });

    const normalizedParticipantId = String(participantId).replace(/"/g, '');
    let photoUrl = null;
    try {
      photoUrl = await uploadProfilePhoto(config, normalizedParticipantId, photoDataUrl);
    } catch (error) {
      console.warn(`Profile photo upload skipped: ${error.message}`);
    }

    await supabaseRequest(config, `/participants?id=eq.${normalizedParticipantId}`, {
      method: 'PATCH',
      body: {
        display_name: `${firstName} ${lastName}`.replace(/\s+/g, ' ').trim(),
        photo_url: photoUrl,
        payment_provider: 'galiopay',
      },
    });

    const referenceId = `raffle_${edition.edition_number}_${normalizedParticipantId.replace(/-/g, '')}`;
    const successUrl = `${config.publicSiteUrl}/?payment=success&participant_id=${encodeURIComponent(normalizedParticipantId)}`;
    const failureUrl = `${config.publicSiteUrl}/?payment=failure&participant_id=${encodeURIComponent(normalizedParticipantId)}`;

    const paymentLink = await createPaymentLink(config, {
      items: [
        {
          title: 'Chances',
          quantity: 1,
          unitPrice: selectedPackage.price,
          currencyId: 'ARS',
          imageUrl: `${config.publicSiteUrl}/favicon.ico`,
        },
      ],
      referenceId,
      notificationUrl: `${config.publicSiteUrl}/.netlify/functions/galiopay-webhook`,
      backUrl: {
        success: successUrl,
        failure: failureUrl,
      },
      sandbox: config.sandboxMode,
    });

    const providerReference = extractPaymentLinkId(paymentLink.url);

    await supabaseRequest(config, '/payment_sessions', {
      method: 'POST',
      body: {
        participant_id: normalizedParticipantId,
        edition_id: edition.edition_id,
        package_id: packageId,
        provider: 'galiopay',
        reference_id: referenceId,
        provider_reference: providerReference,
        proof_token: paymentLink.proofToken || null,
        checkout_url: paymentLink.url,
        amount: selectedPackage.price,
        currency: 'ARS',
        status: 'pending',
        provider_status: 'pending',
      },
    });

    await supabaseRequest(config, `/participants?id=eq.${normalizedParticipantId}`, {
      method: 'PATCH',
      body: {
        payment_link_url: paymentLink.url,
        payment_ref: referenceId,
        payment_metadata: {
          provider_reference: providerReference,
          proof_token: paymentLink.proofToken || null,
        },
      },
    });

    return json(200, {
      checkoutUrl: paymentLink.url,
      participantId: normalizedParticipantId,
      referenceId,
    });
  } catch (error) {
    return json(500, {
      error: 'Could not create Galiopay checkout',
      details: error.message,
    });
  }
};
