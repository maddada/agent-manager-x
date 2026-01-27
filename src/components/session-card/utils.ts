// LocalStorage keys for session custom data
const CUSTOM_NAMES_KEY = 'agent-manager-x-custom-names';
const CUSTOM_URLS_KEY = 'agent-manager-x-custom-urls';

export function getCustomNames(): Record<string, string> {
  try {
    const stored = localStorage.getItem(CUSTOM_NAMES_KEY);
    return stored ? JSON.parse(stored) : {};
  } catch {
    return {};
  }
}

export function setCustomName(sessionId: string, name: string) {
  const names = getCustomNames();
  if (name.trim()) {
    names[sessionId] = name.trim();
  } else {
    delete names[sessionId];
  }
  localStorage.setItem(CUSTOM_NAMES_KEY, JSON.stringify(names));
}

export function getCustomUrls(): Record<string, string> {
  try {
    const stored = localStorage.getItem(CUSTOM_URLS_KEY);
    return stored ? JSON.parse(stored) : {};
  } catch {
    return {};
  }
}

export function setCustomUrl(sessionId: string, url: string) {
  const urls = getCustomUrls();
  if (url.trim()) {
    urls[sessionId] = url.trim();
  } else {
    delete urls[sessionId];
  }
  localStorage.setItem(CUSTOM_URLS_KEY, JSON.stringify(urls));
}
