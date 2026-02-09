type ElectrobunConfig = {
  app: {
    name: string;
    identifier: string;
    version: string;
  };
  build: {
    copy: Record<string, string>;
    mac?: {
      bundleCEF?: boolean;
    };
    linux?: {
      bundleCEF?: boolean;
    };
    win?: {
      bundleCEF?: boolean;
    };
  };
};

export default {
  app: {
    name: 'Agent Manager X',
    identifier: 'sh.madda.agentmanagerx',
    version: '0.1.19',
  },
  build: {
    copy: {
      'dist/index.html': 'views/mainview/index.html',
      'dist/assets': 'views/mainview/assets',
      'dist/vite.svg': 'views/mainview/vite.svg',
      'dist/tauri.svg': 'views/mainview/tauri.svg',
    },
    mac: {
      bundleCEF: false,
    },
    linux: {
      bundleCEF: false,
    },
    win: {
      bundleCEF: false,
    },
  },
} satisfies ElectrobunConfig;
