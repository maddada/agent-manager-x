import '@testing-library/jest-dom'

vi.mock('@/platform/native', () => ({
  invoke: vi.fn(),
  openUrl: vi.fn(),
}))
