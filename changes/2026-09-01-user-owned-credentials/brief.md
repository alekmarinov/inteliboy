# 2026-09-01-user-owned-credentials — someone else's keys, not ours

Status: **deferred, deliberately.** Recorded now because the decision that
defers it is being made now, and the reason will not be obvious later.

## What we are about to do, and why it is wrong long-term

The first speaking image will have the Anthropic and Azure keys **baked into
it**. The user's decision, and the right one for development: the alternative
is a box that cannot answer anything until someone has pushed a key to it, and
that is a poor way to find out whether the thing works at all.

It is wrong as a product, and `tools/seed-image.sh` already says why in its own
header:

> A credential inside an image is a credential in every copy of that image, on
> every device flashed from it, in every backup of the build directory, and in
> whatever anyone tars up to send somewhere. Revoking it means reflashing every
> device rather than deleting one file.

There is a second problem the header does not mention, and it is the one that
matters for a product: **they are our keys, not the owner's.** Every device
would spend our quota, on our account, for whatever its owner asked it. That
does not scale past the people in this conversation.

## What has to exist instead

**A device its owner can give their own keys to**, without a rebuild and
without a keyboard where there may not be one. Three parts, none of them
started:

- **Writable state that survives an update.** The data partition, currently on
  hold. A key the owner sets must not be destroyed by the next image, and
  today every writable path is.
- **A way to enter one.** `docs/roadmap.md` stage 9 is "configuration by
  voice", and a key is the one thing nobody will ever read aloud. So: a
  first-boot setup flow — a QR code on the face pointing at a page on the
  device, or a phone on the same network, or a file on a USB stick. The head
  is a screen; it should be used.
- **The store already exists.** `cogiti/src/cogiti/secrets.py` reads one file
  per secret from `state_dir`, mode 600, and `agent_secrets` /
  `speech_secrets` name what each adapter is given. Nothing about it assumes
  who wrote the file. That part is done.

## Not in this change

Everything. This is a marker, not a plan. The plan needs the data partition
first, and that is on hold for a reason the user gave: it wants a first-boot
setup application, and there is no point building the partition before the
thing that would populate it.

## The trap to avoid when it is picked up

Do not make "the owner's key" a config file someone edits over ssh. That works
for us and is exactly why it would ship. The test is a person who has never
seen a terminal, with a box and a phone.
