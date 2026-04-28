const { getConfig } = require('./_lib/env');
const { getPayment, getPaymentLink } = require('./_lib/galiopay');
const { json } = require('./_lib/http');
const { rpc, supabaseRequest } = require('./_lib/supabase-rest');

async function syncApprovedPayment(config, session, providerPaymentId, providerStatus, payload) {
  await rpc(config, 'mark_galiopay_payment', {
    p_reference_id: session.reference_id,
    p_provider_payment_id: providerPaymentId || null,
    p_provider_status: providerStatus || null,
    p_payload: payload || {},
  });
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'GET') {
    return json(405, { error: 'Method not allowed' });
  }

  try {
    const config = getConfig();
    const participantId = event.queryStringParameters?.participant_id;

    if (!participantId) {
      return json(400, { error: 'participant_id is required' });
    }

    const sessions = await supabaseRequest(
      config,
      `/payment_sessions?participant_id=eq.${encodeURIComponent(participantId)}&order=created_at.desc&limit=1`
    );
    const session = sessions[0];

    if (!session) {
      return json(404, { error: 'Payment session not found' });
    }

    let providerStatus = session.provider_status || session.status;
    let providerPaymentId = session.provider_payment_id || null;

    if (session.status !== 'approved' && session.provider_reference && session.proof_token) {
      const paymentLink = await getPaymentLink(config, session.provider_reference, session.proof_token);
      providerStatus = paymentLink.status || providerStatus;
      providerPaymentId = paymentLink.paymentId || providerPaymentId;

      if (providerPaymentId) {
        const payment = await getPayment(config, providerPaymentId);
        providerStatus = payment.status || providerStatus;
        await syncApprovedPayment(config, session, providerPaymentId, providerStatus, {
          paymentLink,
          payment,
        });
      }
    }

    const participantRows = await supabaseRequest(
      config,
      `/participants?id=eq.${encodeURIComponent(participantId)}&select=id,payment_status,payment_ref,display_name`
    );
    const participant = participantRows[0];

    return json(200, {
      participantId,
      paymentStatus: participant?.payment_status || 'pending',
      providerStatus,
      paymentRef: participant?.payment_ref || session.reference_id,
      displayName: participant?.display_name || null,
    });
  } catch (error) {
    return json(500, {
      error: 'Could not verify payment status',
      details: error.message,
    });
  }
};
