import { useState, useEffect } from 'react';
import { AppHeader, AppMainContent } from './components/app';
import {
  Settings,
  useHotkeyInit,
  useMiniViewerInit,
  getDefaultEditor,
  getDisplayMode,
  setDisplayMode,
  type DefaultEditor,
  type DisplayMode,
} from './components/Settings';
import { useSessions } from './hooks/useSessions';
import { useAppInitialization } from './hooks/useAppInitialization';
import { useNotifications } from './hooks/useNotifications';

function App() {
  const [showSettings, setShowSettings] = useState(false);
  const [defaultEditor, setDefaultEditor] = useState<DefaultEditor>(() => getDefaultEditor());
  const [displayMode, setDisplayModeState] = useState<DisplayMode>(() => getDisplayMode());
  const {
    sessions,
    backgroundSessions,
    totalCount,
    waitingCount,
    agentCounts,
    isLoading,
    error,
    refresh,
    killSessionsByType,
    killBackgroundSession,
    killAllBackgroundSessions,
    killInactiveSessions,
    killStaleSessions,
    getInactiveCount,
    getStaleCount,
  } = useSessions();

  // Notifications state for header bell/voice toggle
  const notifications = useNotifications(() => {});

  // Initialize hotkey on app start
  useHotkeyInit();
  useMiniViewerInit();

  // Initialize theme and background image on app start
  useAppInitialization();

  // Refresh default editor when settings close
  useEffect(() => {
    if (!showSettings) {
      setDefaultEditor(getDefaultEditor());
    }
  }, [showSettings]);

  const handleDisplayModeToggle = () => {
    setDisplayModeState((prev) => {
      const next = prev === 'list' ? 'masonry' : 'list';
      setDisplayMode(next);
      return next;
    });
  };

  return (
    <div className='h-screen bg-background flex flex-col select-none overflow-hidden'>
      <AppHeader
        totalCount={totalCount}
        waitingCount={waitingCount}
        agentCounts={agentCounts}
        backgroundSessions={backgroundSessions}
        isLoading={isLoading}
        getInactiveCount={getInactiveCount}
        getStaleCount={getStaleCount}
        killInactiveSessions={killInactiveSessions}
        killStaleSessions={killStaleSessions}
        killSessionsByType={killSessionsByType}
        killBackgroundSession={killBackgroundSession}
        killAllBackgroundSessions={killAllBackgroundSessions}
        onSettingsClick={() => setShowSettings(true)}
        onRefresh={refresh}
        notificationInstalled={notifications.notificationInstalled}
        bellMode={notifications.bellMode}
        bellModeLoading={notifications.bellModeLoading}
        onBellModeToggle={notifications.handleBellModeToggle}
        displayMode={displayMode}
        onDisplayModeToggle={handleDisplayModeToggle}
      />

      {/* Settings Modal */}
      <Settings isOpen={showSettings} onClose={() => setShowSettings(false)} />

      <AppMainContent
        sessions={sessions}
        error={error}
        defaultEditor={defaultEditor}
        displayMode={displayMode}
        onRefresh={refresh}
      />
    </div>
  );
}

export default App;
