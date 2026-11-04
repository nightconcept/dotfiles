// Runs inside the existing container; credentials and the short-lived token stay there.
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
const require = createRequire('/app/package.json');
const input = JSON.parse(await new Promise(resolve => {
  let text = ''; process.stdin.setEncoding('utf8');
  process.stdin.on('data', chunk => text += chunk); process.stdin.on('end', () => resolve(text));
}));
const dispatcher = new (require('undici').Agent)({ headersTimeout: 600000, bodyTimeout: 600000 });
const token = new (require('@nestjs/jwt').JwtService)().sign(input.session,
  { secret: process.env.JWT_SECRET, expiresIn: '15m' });
async function request(path, method = 'GET', body) {
  const response = await fetch('http://127.0.0.1:3000/api/v1/' + path, {
    dispatcher, method, headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(600000),
  });
  if (!response.ok) throw Error(path + ' HTTP ' + response.status);
  return response;
}
async function api(...args) {
  const response = await request(...args);
  return response.status === 204 ? null : response.json();
}
function identity(book) {
  return { folderPath: book.folderPath, title: book.title, subtitle: book.subtitle,
    description: book.description, publisher: book.publisher, publishedDate: book.publishedDate,
    language: book.language, authors: book.authors, genres: book.genres, tags: book.tags,
    providerIds: book.providerIds, seriesMemberships: book.seriesMemberships,
    lockedFields: book.lockedFields, audioMetadata: book.audioMetadata, coverVersion: book.coverVersion };
}
function names(value) { return value.map(item => typeof item === 'string' ? item.toLowerCase() : item.name.toLowerCase()).sort(); }
function verifyPatch(book, patch) {
  for (const [field, value] of Object.entries(patch)) {
    if (field === 'authors') assert.deepEqual(names(book.authors), names(value));
    else if (field === 'audioMetadata') {
      for (const [key, expected] of Object.entries(value)) {
        if (key === 'narrators') assert.deepEqual(names(book.audioMetadata.narrators), names(expected));
        else assert.deepEqual(book.audioMetadata[key], expected);
      }
    } else if (/Id$/.test(field) && field !== 'seriesId') {
      assert.equal(book.providerIds[field] ?? book.providerIds[field.replace(/Id$/, '')], value);
    } else if (field === 'genres' || field === 'tags') assert.deepEqual([...book[field]].sort(), [...value].sort());
    else if (field === 'communityRatings') {
      for (const rating of value) assert.ok(book.communityRatings.some(r => r.provider === rating.provider && Math.abs(r.rating - rating.rating) < 0.00001));
    } else if (field !== 'seriesMemberships') assert.deepEqual(book[field], value);
  }
}
function preserved(before, after, patch = {}) {
  assert.equal(after.rating, before.rating);
  assert.deepEqual(after.lockedFields, before.lockedFields);
  if (before.audioMetadata) {
    assert.equal(after.audioMetadata.durationSeconds, before.audioMetadata.durationSeconds);
    assert.deepEqual(after.audioMetadata.chapters, patch.audioMetadata?.chapters ?? before.audioMetadata.chapters);
  }
  assert.deepEqual(after.files.map(f => f.id).sort(), before.files.map(f => f.id).sort());
}
try {
  let result;
  if (input.operation === 'snapshot') result = await Promise.all(input.ids.map(id => api('books/' + id)));
  else if (input.operation === 'settings') result = await api('libraries');
  else if (input.operation === 'automation') {
    result = [];
    for (const id of input.ids) {
      const before = (await api('libraries')).find(l => l.id === id);
      assert.ok(before);
      await api('libraries/' + id, 'PATCH', { fileWriteEnabled: true, fileRenameEnabled: true,
        ...(input.audio ? { fileWriteAudioEnabled: true } : {}) });
      result.push({ id, before: { fileWriteEnabled: before.fileWriteEnabled, fileRenameEnabled: before.fileRenameEnabled,
        fileWriteAudioEnabled: before.fileWriteAudioEnabled }, after: (await api('libraries')).find(l => l.id === id) });
    }
  } else if (input.operation === 'lookup') {
    result = await api('metadata-fetch/lookup?' + new URLSearchParams({ provider: input.provider, id: input.id }));
  } else if (input.operation === 'search') {
    const query = new URLSearchParams({ bookId: String(input.book.id), title: input.book.title || '',
      author: input.book.authors[0]?.name || '', providers: input.provider,
      mediaKind: input.provider === 'audible' ? 'audiobook' : 'ebook', resultsPerProvider: '5' });
    const response = await request('metadata-fetch/stream?' + query);
    const text = await response.text();
    result = text.split(/\r?\n\r?\n/).flatMap(block => {
      const data = block.split(/\r?\n/).filter(line => line.startsWith('data:')).map(line => line.slice(5).trim()).join('\n');
      try { const event = JSON.parse(data); return event.providerId ? [event] : []; } catch { return []; }
    });
  } else if (input.operation === 'apply') {
    const before = await api('books/' + input.book.id);
    // shortcut: the API has no compare-and-swap; serialize runs that target the same book.
    assert.deepEqual(identity(before), identity(input.book), 'Book changed after preparation; prepare again');
    assert.ok(!Object.keys(input.patch).some(key => before.lockedFields.includes(key)), 'Patch touches a locked field');
    if (before.audioMetadata?.chaptersSource === 'tracks' && before.audioMetadata.chapters?.length) {
      assert.ok(input.patch.audioMetadata?.chapters, 'Preserve track-derived chapters before automatic renaming');
    }
    let coverApplied = false;
    if (input.cover && !before.covers.audio) {
      await api('books/' + before.id + '/cover/from-url?medium=audio', 'POST', { url: input.cover });
      coverApplied = true;
    }
    const save = await api('books/' + before.id + '/metadata?syncFileWrite=true', 'PATCH', input.patch);
    const after = await api('books/' + before.id);
    preserved(before, after, input.patch); verifyPatch(after, input.patch);
    const writeLog = await api('books/' + before.id + '/write-log');
    result = { before, after, write: save.write, libraryAutoWriteEnabled: save.libraryAutoWriteEnabled, coverApplied, writeLog };
  } else if (input.operation === 'audit') {
    const after = await api('books/' + input.book.id);
    preserved(input.book, after, input.patch); verifyPatch(after, input.patch);
    result = { after, embedded: await api('books/' + after.id + '/metadata-from-file'),
      writeLog: await api('books/' + after.id + '/write-log') };
  } else if (input.operation === 'write') {
    result = await api('books/' + input.id + '/write-and-rename', 'POST');
  } else throw Error('Unknown operation');
  console.log(JSON.stringify({ result }));
} catch (error) {
  // Do not print response bodies, tokens, environment, or arbitrary server errors.
  console.log(JSON.stringify({ error: error.message })); process.exitCode = 1;
} finally {
  await dispatcher.close();
}
