import { Session, SessionStatus } from '../types/session';

// Get ordering priority for card stability (only distinguishes active vs idle)
// This prevents card reordering when status flips between thinking/processing/waiting
export function getOrderingPriority(status: SessionStatus): number {
  switch (status) {
    case 'thinking':
    case 'processing':
    case 'waiting':
      return 0; // All active states - same ordering priority
    case 'idle':
      return 1; // Only idle causes reordering
    case 'stale':
      return 2; // Stale sessions at bottom
  }
}

// Merge new sessions with existing order, only reordering when priority changes
export function mergeWithStableOrder(existing: Session[], incoming: Session[]): Session[] {
  if (existing.length === 0) {
    return incoming;
  }

  // Create a map of existing positions by session ID
  const existingOrder = new Map<string, number>();
  existing.forEach((s, idx) => existingOrder.set(s.id, idx));

  // Create a map of existing ordering priorities (coarse: active vs idle)
  const existingPriority = new Map<string, number>();
  existing.forEach(s => existingPriority.set(s.id, getOrderingPriority(s.status)));

  // Check if any session changed ordering tier (only active <-> idle triggers reorder)
  // Status changes within active states (thinking/processing/waiting) don't cause reordering
  let priorityChanged = false;
  for (const session of incoming) {
    const oldPriority = existingPriority.get(session.id);
    const newPriority = getOrderingPriority(session.status);
    if (oldPriority !== undefined && oldPriority !== newPriority) {
      priorityChanged = true;
      break;
    }
  }

  // Also check for new sessions
  const hasNewSessions = incoming.some(s => !existingOrder.has(s.id));

  // If priority changed or new sessions appeared, use backend order
  if (priorityChanged || hasNewSessions) {
    return incoming;
  }

  // Otherwise, preserve existing order but update session data
  const incomingMap = new Map<string, Session>();
  incoming.forEach(s => incomingMap.set(s.id, s));

  // Keep existing order, update with new data
  const result: Session[] = [];
  for (const existingSession of existing) {
    const updated = incomingMap.get(existingSession.id);
    if (updated) {
      result.push(updated);
      incomingMap.delete(existingSession.id);
    }
  }

  // Add any remaining new sessions at the end (shouldn't happen if hasNewSessions check works)
  for (const newSession of incomingMap.values()) {
    result.push(newSession);
  }

  return result;
}
