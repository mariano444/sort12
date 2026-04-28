function json(statusCode, body) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
    body: JSON.stringify(body),
  };
}

function getJsonBody(event) {
  if (!event.body) return {};
  try {
    return JSON.parse(event.body);
  } catch (error) {
    throw new Error('Invalid JSON body');
  }
}

module.exports = {
  getJsonBody,
  json,
};
