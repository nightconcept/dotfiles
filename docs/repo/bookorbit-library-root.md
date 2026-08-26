# BookOrbit library browse root

## Finding

`LIBRARY_BROWSE_ROOT=/books` confines BookOrbit's library-folder picker and
file-path access to `/books`. A separate sibling mount at `/audiobooks` is
therefore not reachable through that picker: it is outside the configured root.

BookOrbit's release notes describe this setting as restricting file-path access,
not merely selecting the initial folder. Its installation guide says that `/books`
hides other container folders, and its example environment file calls it the top
of the library-creation picker.

## Recommended layout

Mount the common host parent once, with BookOrbit's documented container path as
the destination:

```yaml
volumes:
  - /mnt/titan:/books
```

Then retain:

```env
LIBRARY_BROWSE_ROOT=/books
```

The picker can then access both directories as children of its root:

```
/books/Books
/books/Audiobooks
```

Create separate BookOrbit libraries for those folders if their scan rules or
format priorities differ. BookOrbit's library guide explicitly uses
`/books/audiobooks` as the container-side path and recommends separate ebook and
audiobook libraries when their rules differ.

## Primary sources

- [BookOrbit `.env.example`](https://github.com/bookorbit/bookorbit/blob/main/.env.example): `BOOKS_HOST_PATH` is the host library root mounted at `/books`; `LIBRARY_BROWSE_ROOT=/books` hides other container-root folders.
- [BookOrbit Docker Compose file](https://github.com/bookorbit/bookorbit/blob/main/docker-compose.yml): the official Compose layout binds the single `BOOKS_HOST_PATH` to `/books`.
- [BookOrbit installation guide](https://bookorbit.app/installation): describes `/books` as the mount destination and `LIBRARY_BROWSE_ROOT` as the picker root.
- [BookOrbit v2.3.0 release notes](https://github.com/bookorbit/bookorbit/releases/tag/v2.3.0): records that `LIBRARY_BROWSE_ROOT` restricts file-path access.
- [BookOrbit library-creation guide](https://bookorbit.app/creating-a-library): says Docker libraries use container paths such as `/books/audiobooks` and recommends separate libraries for content with different rules.
