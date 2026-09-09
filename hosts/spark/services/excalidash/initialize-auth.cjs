const base = 'http://127.0.0.1:8000';
const headers = {
  'X-Forwarded-Proto': 'https',
  Origin: 'https://draw.harivan.sh',
};

async function request(path, options = {}) {
  const response = await fetch(`${base}${path}`, {
    ...options,
    headers: { ...headers, ...options.headers },
    signal: AbortSignal.timeout(2000),
  });
  const cookie = response.headers.getSetCookie().map(value => value.split(";")[0]).join("; ");
  if (cookie) headers.Cookie = cookie;
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status}`);
  return response.json();
}

(async () => {
  for (let attempt = 0; ; attempt++) {
    try {
      await request('/health');
      break;
    } catch (error) {
      if (attempt >= 30) throw error;
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
  const status = await request('/auth/status');
  if (status.authOnboardingRequired) {
    const { token } = await request('/csrf-token');
    const result = await request('/auth/onboarding-choice', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-csrf-token': token },
      body: JSON.stringify({ enableAuth: true }),
    });
    if (!result.authEnabled) throw new Error('Authentication was not enabled');
    console.log('Authentication enabled; complete first-admin registration with the setup code.');
  } else if (!status.authEnabled) {
    throw new Error('Refusing to serve an instance with authentication disabled');
  }
})().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
