export function convertPathToDirName(path: string): string {
  const normalized = path.startsWith('/') ? path.slice(1) : path;

  let result = '-';
  for (let i = 0; i < normalized.length; i += 1) {
    const c = normalized[i];
    if (c === '/') {
      if (normalized[i + 1] === '.') {
        result += '--';
        i += 1;
      } else {
        result += '-';
      }
    } else {
      result += c;
    }
  }

  return result;
}

export function convertDirNameToPath(dirName: string): string {
  const name = dirName.startsWith('-') ? dirName.slice(1) : dirName;
  const parts = name.split('-');

  if (parts.length === 0) {
    return '';
  }

  const projectsIdx = parts.findIndex((part) => part === 'Projects' || part === 'UnityProjects');

  if (projectsIdx === -1) {
    return `/${name.replace(/-/g, '/')}`;
  }

  const pathParts = parts.slice(0, projectsIdx + 1);
  const projectParts = parts.slice(projectsIdx + 1);

  let path = `/${pathParts.join('/')}`;
  if (projectParts.length === 0) {
    return path;
  }

  path += '/';

  const segments: string[] = [];
  let current = '';
  let inHiddenFolder = false;

  for (const part of projectParts) {
    if (part === '') {
      if (current.length > 0) {
        segments.push(current);
        current = '';
      }
      inHiddenFolder = true;
      continue;
    }

    if (inHiddenFolder) {
      if (current.length === 0) {
        current = `.${part}`;
      } else {
        segments.push(current);
        current = part;
      }
      continue;
    }

    if (current.length === 0) {
      current = part;
    } else {
      current += `-${part}`;
    }
  }

  if (current.length > 0) {
    segments.push(current);
  }

  path += segments.join('/');
  return path;
}
