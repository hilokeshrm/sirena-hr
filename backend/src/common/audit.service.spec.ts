import { changedFields } from './audit.service';

describe('changedFields', () => {
  it('reports only what really changed', () => {
    const before = { designation: 'QA Engineer', workMode: 'HYBRID', phone: '900' };
    expect(changedFields(before, { designation: 'Senior QA Engineer', workMode: 'HYBRID' })).toEqual({
      designation: { from: 'QA Engineer', to: 'Senior QA Engineer' },
    });
  });

  it('leaves out fields the edit never sent', () => {
    expect(changedFields({ a: 1, b: 2 }, { a: 1, b: undefined })).toBeUndefined();
  });

  it('shows a value appearing and a value being cleared', () => {
    expect(changedFields({ preferredName: null }, { preferredName: 'Dev' })).toEqual({
      preferredName: { from: null, to: 'Dev' },
    });
    expect(changedFields({ phone: '900' }, { phone: null })).toEqual({ phone: { from: '900', to: null } });
  });

  it('compares dates by day, not by object', () => {
    const same = changedFields({ joinedOn: new Date('2026-06-30T00:00:00Z') }, { joinedOn: new Date('2026-06-30T00:00:00Z') });
    expect(same).toBeUndefined();
    expect(changedFields({ joinedOn: new Date('2026-06-30T00:00:00Z') }, { joinedOn: new Date('2026-07-01T00:00:00Z') })).toEqual({
      joinedOn: { from: '2026-06-30', to: '2026-07-01' },
    });
  });

  it('compares lists by contents', () => {
    expect(changedFields({ bssids: ['a', 'b'] }, { bssids: ['a', 'b'] })).toBeUndefined();
    expect(changedFields({ bssids: ['a'] }, { bssids: ['a', 'b'] })).toEqual({ bssids: { from: ['a'], to: ['a', 'b'] } });
  });

  it('never writes a password hash or a token to the log', () => {
    expect(changedFields({ passwordHash: 'old', token: 't1' }, { passwordHash: 'new', token: 't2' })).toBeUndefined();
  });
});
