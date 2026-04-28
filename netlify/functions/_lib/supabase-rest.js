async function supabaseRequest(config, path, options = {}) {
  const url = `${config.supabaseUrl}/rest/v1${path}`;
  const response = await fetch(url, {
    method: options.method || 'GET',
    headers: {
      apikey: config.supabaseServiceRoleKey,
      'Content-Type': 'application/json',
      Prefer: options.prefer || 'return=representation',
      ...(options.headers || {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Supabase request failed (${response.status}): ${text}`);
  }

  if (response.status === 204) {
    return null;
  }

  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

async function rpc(config, fnName, body = {}) {
  return supabaseRequest(config, `/rpc/${fnName}`, {
    method: 'POST',
    body,
    prefer: 'params=single-object,return=representation',
  });
}

async function uploadProfilePhoto(config, participantId, dataUrl) {
  if (!dataUrl) return null;

  const match = /^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/.exec(dataUrl);
  if (!match) {
    throw new Error('Unsupported profile image format');
  }

  const mimeType = match[1];
  const extension = mimeType.split('/')[1]?.replace('jpeg', 'jpg') || 'bin';
  const filePath = `${participantId}/profile.${extension}`;
  const uploadUrl = `${config.supabaseUrl}/storage/v1/object/${config.profileBucket}/${filePath}`;

  const response = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      apikey: config.supabaseServiceRoleKey,
      'Content-Type': mimeType,
      'x-upsert': 'true',
    },
    body: Buffer.from(match[2], 'base64'),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Supabase storage upload failed (${response.status}): ${text}`);
  }

  return `${config.supabaseUrl}/storage/v1/object/public/${config.profileBucket}/${filePath}`;
}

module.exports = {
  rpc,
  supabaseRequest,
  uploadProfilePhoto,
};
