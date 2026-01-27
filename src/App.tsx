import { useState, useEffect } from 'react';
import { AppHeader, AppMainContent } from './components/app';
import { Settings, useHotkeyInit, getDefaultEditor, type DefaultEditor } from './components/Settings';
import { useSessions } from './hooks/useSessions';
import { useAppInitialization } from './hooks/useAppInitialization';
import { useNotifications } from './hooks/useNotifications';

function App() {
  const [showSettings, setShowSettings] = useState(false);
  const [defaultEditor, setDefaultEditor] = useState<DefaultEditor>(() => getDefaultEditor());
  const {
    sessions,
    totalCount,
    waitingCount,
    agentCounts,
    isLoading,
    error,
    refresh,
    killSessionsByType,
    killInactiveSessions,
    killStaleSessions,
    getInactiveCount,
    getStaleCount,
  } = useSessions();

  // Notifications state for header bell/voice toggle
  const notifications = useNotifications(() => {});

  // Initialize hotkey on app start
  useHotkeyInit();

  // Initialize theme and background image on app start
  useAppInitialization();

  // Refresh default editor when settings close
  useEffect(() => {
    if (!showSettings) {
      setDefaultEditor(getDefaultEditor());
    }
  }, [showSettings]);

  return (
    <div className='min-h-screen bg-background flex flex-col select-none'>
      <AppHeader
        totalCount={totalCount}
        waitingCount={waitingCount}
        agentCounts={agentCounts}
        isLoading={isLoading}
        getInactiveCount={getInactiveCount}
        getStaleCount={getStaleCount}
        killInactiveSessions={killInactiveSessions}
        killStaleSessions={killStaleSessions}
        killSessionsByType={killSessionsByType}
        onSettingsClick={() => setShowSettings(true)}
        onRefresh={refresh}
        notificationInstalled={notifications.notificationInstalled}
        bellMode={notifications.bellMode}
        bellModeLoading={notifications.bellModeLoading}
        onBellModeToggle={notifications.handleBellModeToggle}
      />

      {/* Settings Modal */}
      <Settings isOpen={showSettings} onClose={() => setShowSettings(false)} />

      <AppMainContent
        sessions={sessions}
        error={error}
        defaultEditor={defaultEditor}
        onRefresh={refresh}
      />
    </div>
  );
}

export default App;
