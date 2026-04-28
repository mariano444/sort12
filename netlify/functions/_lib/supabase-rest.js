function buildSupabaseHeaders(apiKey, extraHeaders = {}) {
  const headers = {
    apikey: apiKey,
    ...extraHeaders,
  };

  // Legacy anon/service_role keys are JWTs and still work in Authorization.
  // New sb_publishable/sb_secret keys must NOT be sent as Bearer tokens.
  if (!String(apiKey).startsWith('sb_')) {
    headers.Authorization = `Bearer ${apiKey}`;
  }

  return headers;
}

async function supabaseRequest(config, path, options = {}) {
  const url = `${config.supabaseUrl}/rest/v1${path}`;
  const response = await fetch(url, {
    method: options.method || 'GET',
    headers: buildSupabaseHeaders(config.supabaseServiceRoleKey, {
      'Content-Type': 'application/json',
      Prefer: options.prefer || 'return=representation',
      ...(options.headers || {}),
    }),
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

async function ensureStorageBucket(config) {
  const bucketUrl = `${config.supabaseUrl}/storage/v1/bucket/${config.profileBucket}`;
  const checkResponse = await fetch(bucketUrl, {
    headers: buildSupabaseHeaders(config.supabaseServiceRoleKey),
  });

  if (checkResponse.ok) {
    return;
  }

  const checkText = await checkResponse.text();
  const bucketMissing =
    checkResponse.status === 404 ||
    (checkResponse.status === 400 && /bucket not found/i.test(checkText));

  if (!bucketMissing) {
    throw new Error(`Supabase storage bucket check failed (${checkResponse.status}): ${checkText}`);
  }

  const createResponse = await fetch(`${config.supabaseUrl}/storage/v1/bucket`, {
    method: 'POST',
    headers: buildSupabaseHeaders(config.supabaseServiceRoleKey, {
      'Content-Type': 'application/json',
    }),
    body: JSON.stringify({
      id: config.profileBucket,
      name: config.profileBucket,
      public: true,
      file_size_limit: '2097152',
      allowed_mime_types: ['image/jpeg', 'image/png', 'image/webp'],
    }),
  });

  if (!createResponse.ok) {
    const text = await createResponse.text();
    const alreadyExists =
      createResponse.status === 409 ||
      /already exists/i.test(text);

    if (!alreadyExists) {
      throw new Error(`Supabase storage bucket create failed (${createResponse.status}): ${text}`);
    }
  }
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

  await ensureStorageBucket(config);

  const response = await fetch(uploadUrl, {
    method: 'POST',
    headers: buildSupabaseHeaders(config.supabaseServiceRoleKey, {
      'Content-Type': mimeType,
      'x-upsert': 'true',
    }),
    body: Buffer.from(match[2], 'base64'),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Supabase storage upload failed (${response.status}): ${text}`);
  }

  return `${config.supabaseUrl}/storage/v1/object/public/${config.profileBucket}/${filePath}`;
}

module.exports = {
  buildSupabaseHeaders,
  rpc,
  supabaseRequest,
  uploadProfilePhoto,
};
