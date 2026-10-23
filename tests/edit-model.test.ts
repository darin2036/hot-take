import {it, expect} from 'vitest';
import {changeRange, length} from '../src/edit-model';
it('removes a middle range and joins the retained sections', () => {
  const original = [{start: 0, end: 10}];
  const cut = changeRange(original, 3, 6);
  expect(cut).toEqual([
    {start: 0, end: 3},
    {start: 6, end: 10},
  ]);
  expect(length(cut)).toBe(7);
  expect(original).toEqual([{start: 0, end: 10}]);
});
it('trims across prior cuts without bringing deleted content back', () => {
  expect(
    changeRange(
      [
        {start: 0, end: 3},
        {start: 6, end: 10},
      ],
      1,
      8,
      true,
    ),
  ).toEqual([
    {start: 1, end: 3},
    {start: 6, end: 8},
  ]);
});
it('supports multiple cuts and rejects invalid or empty edits', () => {
  expect(
    changeRange(
      [
        {start: 0, end: 3},
        {start: 6, end: 10},
      ],
      2,
      8,
    ),
  ).toEqual([
    {start: 0, end: 2},
    {start: 8, end: 10},
  ]);
  for (const range of [
    [0, 10],
    [2, 1],
    [NaN, 4],
    [-1, 3],
  ])
    expect(() => changeRange([{start: 0, end: 10}], ...(range as [number, number]))).toThrow();
});
