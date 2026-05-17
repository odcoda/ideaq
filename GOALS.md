This is a very simple, information-dense project-management system.
There is a single page; the page has one table of ideas per
project. The table shows all the different fields above and lets the person
using the dashboard prioritize, sort, edit, and track ideas. All changes
made in the UI are immediately mirrored in the backing storage.

Note that changes to the names also need to change the 'related' fields of
other idea entries related to this one. This isn't beautiful but it works.

## local storage format

Each project has a queue file.

Write all the ideas down in json format. Each project's queue file should be a
simple list of idea records with the following structure

{
  "name": "twow_index",
  "human_idea": "gather all text from other asoiaf books to find references",
  "difficulty": "M",
  "related": ["twow_generate", "character_index", "character_sheet"],
  "priority": "none"
  "description": "Index character appearances George R. R. Martin's Song
  of Ice and Fire series. Given a character, major or minor, be able to look up
  all locations where they appear or are referenced (even if just by epithet or
  allusion). Load surrounding text for each location on request."
}

## sync

To support multiple clients (ios and web), there is also a sync server. Note that
this server only needs to support a single user (me) so don't overengineer the
server itself or the backing infra.

There should be some authentication to make sure random people aren't able to
read/write from my server, some diff application / resolution
functionality on the server (if there's a conflict, try to incorporate both
sets of changes sensibly whenever possible), then have functionality in both
ios and web clients to sync down (read) and sync up (write) changes

The server storage should basically mirror the local format. Just store json
blobs, nothing fancy. It probably makes sense to put them in a database or
key-value store or something.

The server will be hosted on some cloud provider (aws?)

## map

ios/ -- ios app (data stored in local storage)
server/ -- sync server
web/ -- web app (data stored locally in a git repo)
