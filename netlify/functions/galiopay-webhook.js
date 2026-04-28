const { getConfig } = require('./_lib/env');
const { getPayment } = require('./_lib/galiopay');
const { getJsonBody, json } = require('./_lib/http');
const { rpc } = require('./_lib/supabase-rest');

function extractPayload(body) {
  const candidate = body?.data || body;
  const paymentId =
    candidate?.paymentId ||
    candidate?.payment_id ||
    candidate?.payment?.id ||
    candidate?.id ||
    null;
  const status =
    candidate?.status ||
    candidate?.paymentStatus ||
    candidate?.payment?.status ||
    null;
  const referenceId =
    candidate?.referenceId ||
    candidate?.reference_id ||
    candidate?.payment?.referenceId ||
    candidate?.payment?.reference_id ||
    null;

  return {
    paymentId,
    referenceId,
    status,
  };
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  try {
    const config = getConfig();
    const body = getJsonBody(event);
    let { paymentId, referenceId, status } = extractPayload(body);
    let payment = null;

    if (paymentId) {
      payment = await getPayment(config, paymentId);
      referenceId = referenceId || payment.referenceId || payment.reference_id;
      status = status || payment.status;
    }

    if (!referenceId) {
      return json(202, { received: true, skipped: true, reason: 'referenceId not found' });
    }

    await rpc(config, 'mark_galiopay_payment', {
      p_reference_id: referenceId,
      p_provider_payment_id: paymentId || null,
      p_provider_status: status || null,
      p_payload: {
        webhook: body,
        payment,
      },
    });

    return json(200, { received: true });
  } catch (error) {
    return json(500, {
      error: 'Webhook processing failed',
      details: error.message,
    });
  }
};
