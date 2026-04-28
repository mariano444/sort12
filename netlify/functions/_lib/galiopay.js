function buildHeaders(config) {
  return {
    Authorization: `Bearer ${config.galiopayApiKey}`,
    'x-client-id': config.galiopayClientId,
    'Content-Type': 'application/json',
  };
}

function extractPaymentLinkId(paymentUrl) {
  const match = /\/payment\/([^?]+)/.exec(paymentUrl || '');
  return match ? match[1] : null;
}

async function createPaymentLink(config, payload) {
  const response = await fetch(`${config.galiopayBaseUrl}/api/payment-links`, {
    method: 'POST',
    headers: buildHeaders(config),
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Galiopay create payment link failed (${response.status}): ${text}`);
  }

  return response.json();
}

async function getPayment(config, paymentId) {
  const response = await fetch(`${config.galiopayBaseUrl}/api/payments/${paymentId}`, {
    headers: buildHeaders(config),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Galiopay get payment failed (${response.status}): ${text}`);
  }

  return response.json();
}

async function getPaymentLink(config, paymentLinkId, proofToken) {
  const response = await fetch(
    `${config.galiopayBaseUrl}/api/payment-links/${paymentLinkId}?proof=${encodeURIComponent(proofToken)}`
  );

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Galiopay get payment link failed (${response.status}): ${text}`);
  }

  return response.json();
}

module.exports = {
  createPaymentLink,
  extractPaymentLinkId,
  getPayment,
  getPaymentLink,
};
