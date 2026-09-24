// dxeinject (Linux) — DXEInject-compatible EnableGop inserter for Mac Pro 4,1/5,1.
//
// dosdude1's DXEInject is UEFITool's 0.2x FfsEngine wrapped in a macOS binary: it
// parses the BootROM, finds the DXE driver BAE7599F-3C6B-43B7-BDF0-9CE07AA91AA6,
// inserts the given .ffs AFTER it and rebuilds the image. This is the same
// operation on the same engine (UEFITool 0.28.0, BSD-2), built for Linux so the
// GopForge-Live USB can patch without macOS.
//
// usage: dxeinject <in.rom> <out.rom> <file.ffs>
// exit:  0 ok · 2 file · 3 parse · 4 anchor missing/ambiguous · 5 insert · 6 rebuild · 7 already present · 64 usage
#include <QCoreApplication>
#include <QFile>
#include <cstdio>
#include "../ffsengine.h"
#include "../treemodel.h"
#include "../types.h"

// Anchor GUID BAE7599F-3C6B-43B7-BDF0-9CE07AA91AA6 in on-disk byte order.
static const char* ANCHOR_HEX = "9f59e7ba6b3cb743bdf09ce07aa91aa6";

static QModelIndex findFile(TreeModel* m, const QModelIndex& idx, const QByteArray& guid, int& hits) {
  QModelIndex first;
  if (m->type(idx) == Types::File && m->header(idx).left(16) == guid) { hits++; first = idx; }
  for (int i = 0; i < m->rowCount(idx); i++) {
    QModelIndex r = findFile(m, idx.child(i, 0), guid, hits);
    if (!first.isValid() && r.isValid()) first = r;
  }
  return first;
}

static bool readAll(const char* path, QByteArray& out) {
  QFile f(path);
  if (!f.open(QFile::ReadOnly)) return false;
  out = f.readAll();
  return true;
}

int main(int argc, char** argv) {
  QCoreApplication app(argc, argv);
  if (argc != 4) {
    fprintf(stderr, "usage: %s <in.rom> <out.rom> <file.ffs>\n", argv[0]);
    return 64;
  }
  QByteArray rom, ffs;
  if (!readAll(argv[1], rom)) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }
  if (!readAll(argv[3], ffs)) { fprintf(stderr, "cannot read %s\n", argv[3]); return 2; }

  FfsEngine engine;
  TreeModel* model = engine.treeModel();
  UINT8 r = engine.parseImageFile(rom);
  if (r) { fprintf(stderr, "parse failed: %s\n", qPrintable(errorMessage(r))); return 3; }

  int hits = 0;
  QModelIndex anchor = findFile(model, model->index(0, 0), QByteArray::fromHex(ANCHOR_HEX), hits);
  if (!anchor.isValid()) { fprintf(stderr, "insertion point BAE7599F-3C6B-43B7-BDF0-9CE07AA91AA6 not found\n"); return 4; }
  if (hits != 1) { fprintf(stderr, "insertion point found %d times; refusing\n", hits); return 4; }

  // Never insert a second copy of a driver that is already there.
  if (ffs.size() < 24) { fprintf(stderr, "%s is not an FFS file\n", argv[3]); return 2; }
  int dup = 0;
  findFile(model, model->index(0, 0), ffs.left(16), dup);
  if (dup) { fprintf(stderr, "this driver is already in the image; refusing to insert it again\n"); return 7; }

  r = engine.insert(anchor, ffs, CREATE_MODE_AFTER);
  if (r) { fprintf(stderr, "insert failed: %s\n", qPrintable(errorMessage(r))); return 5; }

  QByteArray out;
  r = engine.reconstructImageFile(out);
  if (r) { fprintf(stderr, "rebuild failed: %s\n", qPrintable(errorMessage(r))); return 6; }
  if (out.size() != rom.size()) { fprintf(stderr, "rebuilt image changed size (%d -> %d); refusing\n", rom.size(), out.size()); return 6; }

  QFile o(argv[2]);
  if (!o.open(QFile::WriteOnly) || o.write(out) != out.size()) { fprintf(stderr, "cannot write %s\n", argv[2]); return 2; }
  o.close();
  fprintf(stderr, "EnableGop inserted after BAE7599F: %s (%d bytes)\n", argv[2], out.size());
  return 0;
}
