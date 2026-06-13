const { test } = require("node:test");
const assert = require("node:assert/strict");
const n = require("../lib/naming");

test("constants: 6 banks of 24 = 144 slots", () => {
  assert.equal(n.BANK_SIZE, 24);
  assert.equal(n.NUM_BANKS, 6);
  assert.equal(n.TOTAL_SLOTS, 144);
});

test("parsePrefix splits NNNN_ prefix", () => {
  assert.deepEqual(n.parsePrefix("0007_foo.mp3"), { num: 7, rest: "foo.mp3" });
  assert.deepEqual(n.parsePrefix("foo.mp3"), { num: null, rest: "foo.mp3" });
});

test("pad4 zero-pads", () => {
  assert.equal(n.pad4(1), "0001");
  assert.equal(n.pad4(144), "0144");
});

test("bankOfSlot respects the 24-slot boundary", () => {
  assert.equal(n.bankOfSlot(1), 1);
  assert.equal(n.bankOfSlot(24), 1);
  assert.equal(n.bankOfSlot(25), 2);
  assert.equal(n.bankOfSlot(144), 6);
});

test("prefixForSlot encodes bank*100 + position", () => {
  assert.equal(n.prefixForSlot(1), 101);
  assert.equal(n.prefixForSlot(24), 124);
  assert.equal(n.prefixForSlot(25), 201);
  assert.equal(n.prefixForSlot(144), 624);
});

test("slotFromPrefix is the inverse, rejecting invalid prefixes", () => {
  assert.equal(n.slotFromPrefix(101), 1);
  assert.equal(n.slotFromPrefix(124), 24);
  assert.equal(n.slotFromPrefix(201), 25);
  assert.equal(n.slotFromPrefix(624), 144);
  assert.equal(n.slotFromPrefix(125), null); // position 25 > 24
  assert.equal(n.slotFromPrefix(701), null); // bank 7 > 6
  assert.equal(n.slotFromPrefix(1), null); // old-style prefix, not bank*100+pos
});

test("finalName strips old prefix and applies the new bank*100+pos prefix", () => {
  assert.equal(n.finalName(1, "0099_clownhorn.mp3"), "0101_clownhorn.mp3");
  assert.equal(n.finalName(25, "airhorn.mp3"), "0201_airhorn.mp3");
  assert.equal(n.finalName(144, "0301_x.mp3"), "0624_x.mp3");
});

test("buildInitialOrder: bank*100+pos prefixes claim their slot, unprefixed alpha-fill, dense", () => {
  const order = n.buildInitialOrder([
    "0201_b2.mp3", // bank 2 pos 1 -> slot 25
    "0101_a1.mp3", // bank 1 pos 1 -> slot 1
    "zebra.mp3",
    "apple.mp3",
  ]);
  assert.deepEqual(order, [
    "0101_a1.mp3",
    "apple.mp3",
    "zebra.mp3",
    "0201_b2.mp3",
  ]);
});

test("buildInitialOrder: prefix collisions bump to the next free slot, dense output", () => {
  const order = n.buildInitialOrder([
    "0101_a.mp3",
    "0101_b.mp3",
    "0201_c.mp3",
  ]);
  assert.deepEqual(order, ["0101_a.mp3", "0101_b.mp3", "0201_c.mp3"]);
});

test("buildInitialOrder: old-style prefixes (0001) are treated as unprefixed", () => {
  // Not bank*100+pos -> sorted alphabetically so they get fresh slots/names.
  const order = n.buildInitialOrder(["0050_b.mp3", "0001_a.mp3"]);
  assert.deepEqual(order, ["0001_a.mp3", "0050_b.mp3"]);
});
