# Retro IIS File Cabinet

A single-page ASP.NET Web Forms file cabinet for IIS 8+.

It provides a retro-style browser UI for:

- File listing
- File download
- Chunked upload up to 10 GB
- Folder creation
- File and folder deletion

## Files

- `default.aspx` - self-contained file manager page.
- `web.config` - IIS/ASP.NET upload and default document configuration.

## Deploy

Create an IIS application or folder, then copy these files into it:

```text
default.aspx
web.config
```

The app stores shared files under:

```text
files/
```

Make sure the IIS application pool identity can modify that folder. For example:

```bat
icacls C:\inetpub\wwwroot\a\files /grant *S-1-5-32-568:(OI)(CI)(M)
```

## Notes

Large uploads are split in the browser into 64 MB chunks and reassembled on the server. The configured single-request limit is 200 MB, while the UI-level file limit is 10 GB.
