#
# Tsundoku - OPDS ebook catalog server
# Copyright 2016 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3 License, see LICENSE file
#

import asyncdispatch,
  base64,
  jester,
  logging,
  os,
  parseopt,
  strutils,
  times

from algorithm import sortedByIt
from posix import onSignal, SIGINT, SIGTERM
from strutils import endswith, strip

var disk_path = ""

type
  Author* = object
    name, uri: string

  OPDSLink* = ref object
    href, rel, linktype: string

  OPDSEntry* = ref object
    category_label, category_term, content, title, language: string
    issue_date, rights, isbn, publisher, summary, uuid: string
    #updated: TimeInfo
    authors: seq[Author]
    links: seq[OPDSLink]

include "opds.tmpl"

proc encode_path(url_path, item_path: string): string =
  "/" & base64.encode(url_path / item_path, newline="")

proc gen_uuid(path: string): string =
  ## Generate random looking v4 UUID
  ## xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx
  var hash: array[0..14, int8]
  for pos, c in path:
    let p = pos mod 15
    hash[p] = hash[p] xor ord(c).int8

  var hex_str = newStringOfCap(30)
  for v in hash:
    hex_str.add v.toHex()

  "$#-$#-4$#-8$#-$#" % [
    hex_str[0..8],
    hex_str[9..13],
    hex_str[14..17],
    hex_str[18..21],
    hex_str[22..30],
  ]


proc gen_catalog(url_path: string): string =
  ## Generate catalog
  debug "Generating page ", url_path
  var entries: seq[OPDSEntry] = @[]
  let t = getTime().getLocalTime()

  let scan_path = disk_path / url_path
  debug "Searching ", scan_path
  var displayed_catalogs = 0
  var displayed_files = 0
  for item_kind, item_path in walkDir(scan_path, relative=true):
    case item_kind:
    of pcDir:
      # Generate OPDS subsection for a directory
      debug "Showing catalog ", item_path
      displayed_catalogs.inc
      let uuid = gen_uuid(url_path / item_path)
      let sub = OPDSEntry(title:item_path, uuid:uuid)
      #sub.updated = t
      let link = OPDSLink(
        href:encode_path(url_path, item_path),
        rel:"sub",
        linktype:"application/atom+xml;profile=opds-catalog"
      )
      #link.href="/ebooks/search.opds/?sort_order=random"
      sub.links = @[link]
      entries.add sub

    of pcFile:
      # Generate book for an epub file
      if not item_path.endswith(".epub"):
        continue

      debug "Showing file ", item_path
      displayed_files.inc
      let title = item_path[0..^6]
      let book = OPDSEntry(title:title)
      #book.updated = t

      let link = OPDSLink(
        href:encode_path(url_path, item_path),
        rel:"http://opds-spec.org/acquisition",
        linktype:"application/epub+zip"
      )
      book.links = @[link]
      entries.add book

    else: # ignore symlinks
      discard

  debug "Showing ", $displayed_catalogs, " catalogs and ", $displayed_files, " files"
  entries = entries.sortedByIt(it.title)

  return generate_opds("Tsundoku", t, entries)





# Jester settings and routing

settings:
  port = Port(8080)

routes:

  get "/":
    resp gen_catalog("/")

  get "/@path":
    let url_path = base64.decode(@"path")
    let abs_path = disk_path / url_path
    # Prevent traversals: "disk_path / url_path" must be >= disk_path
    if (not abs_path.isAbsolute) or cmpPaths(disk_path, abs_path) > 0:
      resp Http500, "Incorrect path"

    if abs_path.endswith(".epub"):
      info "Serving file ", abs_path
      resp $abs_path.readFile()

    else:
      resp gen_catalog(url_path)


onSignal(SIGINT, SIGTERM):
  echo "Exiting"
  quit()

proc writeHelp() =
  ## Write help
  echo """
  Usage: tsundoku <ebook_path>
  [-h]                this help
  """

proc main() =
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      disk_path = key
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        writeHelp()
        quit()

    of cmdEnd: discard

  runForever()

when isMainModule:
  main()




