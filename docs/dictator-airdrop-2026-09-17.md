# Dictator AirDrop metadata — task6256, 17 September 2026

User explicitly selected Claude through Pimp for the first AirDrop adapter. This patch exposes only local opaque composer metadata to Dictator. No draft text, filenames or URLs appear in the marker. The main/Code/new-chat routes are recognized; an unidentified popout is unavailable.

Within `myclaude-image-undo-composer-v1`, a direct child `myclaude-composer-attachments-v1` has role img and aria-label JSON `{v:1,session,generation,revision,count,members:[String]}`. Count includes known image and document attachment cards. Loading, unknown structures, failures and ambiguous composers remove the marker. Chat/editor/submit/reset/removal changes invalidate generation. It confirms draft-card growth, not server acceptance or an atomic server attachment reservation.

Base24ffecd (completed WF70/WF71), VERSION wf70-b-1. Implemented in an isolated checkout while WF70 was active; its source, Swift work and live files were preserved. Independent Astra High review found the ordinary /chat UUID omission; it was fixed with same-composer navigation regression. Canonical tools/test.sh --js: 406 JS and42 CLI pass; loader v7 unchanged. No Swift code or bundle changed. Native AX mapping and actual phone AirDrop must be reported separately from these tests.

Dictator owns download watching, original-file preservation, exact editor/window/session checks, shared serialized clipboard delivery, capacity20 check and one-paste confirmation. It stops on unknown state without retry. Existing documents count too, but concurrent manual changes between count and native paste cannot be made atomic by this read-only marker.
