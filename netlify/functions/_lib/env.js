function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function getOptionalEnv(name, fallback) {
  const value = process.env[name];
  return value || fallback;
}

function getConfig() {
  return {
    supabaseUrl: getOptionalEnv('SUPABASE_URL', 'https://nksszbvoiqarfjlrfmor.supabase.co'),
    supabaseServiceRoleKey: requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
    galiopayClientId: requireEnv('GALIOPAY_CLIENT_ID'),
    galiopayApiKey: requireEnv('GALIOPAY_API_KEY'),
    publicSiteUrl: requireEnv('PUBLIC_SITE_URL').replace(/\/$/, ''),
    galiopayBaseUrl: (process.env.GALIOPAY_BASE_URL || 'https://pay.galio.app').replace(/\/$/, ''),
    profileBucket: process.env.SUPABASE_PROFILE_BUCKET || 'profile-photos',
    sandboxMode: String(process.env.GALIOPAY_SANDBOX || '').toLowerCase() === 'true',
  };
}

module.exports = {
  getConfig,
};
