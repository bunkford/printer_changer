#========================================================================
#
#                      Default Printer Changer
#                (c) Copyright 2019 Duncan Clarke
#
#========================================================================

# icon and version resource file, 64-bit by default:
#   windres printer_changer.rc -O coff -o printer_changer.o
# a 32-bit build links its own (windres --target=pe-i386), named with -d:resourceObject=<file>
const resourceObject {.strdefine.} = "printer_changer.o"
{.link: resourceObject.}

import
  wNim,
  wDarkMode,  # nimble install https://github.com/bunkford/wDarkMode@#HEAD
  winim/lean,
  winim/inc/winspool,
  winim/inc/tlhelp32,
  os,
  osproc,
  strutils,
  algorithm

# "printer_changer --quit" closes the copies of this program that are already running: the
# installer runs it before it replaces or removes the program, which Windows can't do while
# it is in use. A running copy answers this message by exiting.
let quitMessage = RegisterWindowMessage("PrinterChangerQuit")

proc quit_running_copies() =
  let
    me = GetCurrentProcessId()
    name = getAppFilename().extractFilename
  var running: seq[HANDLE]
  let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
  if snapshot != INVALID_HANDLE_VALUE:
    var entry: PROCESSENTRY32
    entry.dwSize = DWORD sizeof(entry)
    if Process32First(snapshot, &entry) != 0:
      while true:
        if entry.th32ProcessID != me and cmpIgnoreCase(nullTerminated($$entry.szExeFile), name) == 0:
          let process = OpenProcess(SYNCHRONIZE or PROCESS_TERMINATE, FALSE, entry.th32ProcessID)
          if process != 0: running.add process
        if Process32Next(snapshot, &entry) == 0: break
    CloseHandle(snapshot)
  if running.len == 0: return
  # ask them to exit (so each takes its tray icon with it), and end any that has not after 5 seconds
  PostMessage(HWND_BROADCAST, quitMessage, 0, 0)
  for process in running:
    if WaitForSingleObject(process, 5000) != WAIT_OBJECT_0:
      TerminateProcess(process, 0)
      WaitForSingleObject(process, 2000)
    CloseHandle(process)

if paramCount() > 0 and paramStr(1) == "--quit":
  quit_running_copies()
  quit(0)

type
  # A menu ID in wNim is type of wCommandID (distinct int) or any enum type.
  MenuID = enum
    idExit = wIdUser, idProperties, idQueue

proc get_default_printer(): string = # get the default printer
  var needed: DWORD
  GetDefaultPrinter(nil, &needed)
  if needed < 2: return "" # no default printer (no printers at all)
  var buffer = newWString(int needed)
  GetDefaultPrinter(&buffer, &needed)
  return $(buffer)[0 .. ^2] # trim trailing null character

# load icons
const exit = staticRead(r"icons/goodbye.ico") 
let exitBitmap = Bitmap(Image(exit).scale(16, 16))

const printer = staticRead(r"icons/print.ico")
let printerBitmap = Bitmap(Image(printer).scale(16, 16))

const queue = staticRead(r"icons/queue.ico")
let queueBitmap = Bitmap(Image(queue).scale(16, 16))

const properties = staticRead(r"icons/gear.ico")
let propertiesBitmap = Bitmap(Image(properties).scale(16, 16))

const ico = staticRead(r"icons/printer.ico")
let icon = Icon(ico)

const right = staticRead(r"icons/right.ico")
let rightBitmap = Bitmap(Image(right).scale(16, 16))

var app = App()

#enable dark mode
app.enableDarkMode()

var frame = Frame()
frame.icon = icon
frame.setTrayIcon(icon)

# menu to change default printer
var menuDefaultPrinter = Menu()
menuDefaultPrinter.append(idProperties, "Properties", "Default Printer Properties", propertiesBitmap)
menuDefaultPrinter.append(idQueue, "Queue", "Default Printer Properties", queueBitmap)

# menu for when you right click on tray icon
var trayMenu = Menu() 
trayMenu.appendSeparator()
trayMenu.appendSubMenu(menuDefaultPrinter, get_default_printer(), "Default Printer", rightBitmap)
trayMenu.appendSeparator()
trayMenu.append(idExit, "E&xit", "Exit the program.", exitBitmap)

# iterate over local printers and network printers we've made a connection to
var menuPrinters = Menu()
var needed, returned: DWORD
EnumPrinters(PRINTER_ENUM_CONNECTIONS or PRINTER_ENUM_LOCAL, nil, 2, nil, 0, &needed, &returned)
var buffer = newString(needed)
let pInfo = cast[LPBYTE](&buffer)
let printers = cast[ptr UncheckedArray[PRINTER_INFO_2]](pInfo)
EnumPrinters(PRINTER_ENUM_CONNECTIONS or PRINTER_ENUM_LOCAL, nil, 2, pInfo, needed, &needed, &returned)

type PrinterEntry = object
  name: string
  attributes: DWORD
  portName: string

var printer_entries: seq[PrinterEntry]
for i in 0..<returned:
  printer_entries.add(PrinterEntry(
    name: $(printers[i].pPrinterName),
    attributes: printers[i].Attributes,
    portName: $(printers[i].pPortName)
  ))

# sort by name
printer_entries.sort(proc(a, b: PrinterEntry): int = cmp(a.name, b.name))

for i in 0..<printer_entries.len:
  menuPrinters.append(wCommandID i, printer_entries[i].name, printer_entries[i].name, printerBitmap)  
  
# insert sub menu containing printers
trayMenu.insertSubMenu(0, menuPrinters, "Set Printer", "Change Default Printer.", printerBitmap)

proc update_printer_menu(): void = # check default printer and mark it checked
  var default = get_default_printer()
  # uncheck all items first
  for i in trayMenu.getSubMenu(0):
    i.check(false)
  # check the default printer
  for i in trayMenu.getSubMenu(0):
    if $(i.text) == default:
      i.check(true)

frame.idExit do ():
  frame.delete

frame.connect(quitMessage) do (): # "printer_changer --quit" asks every running copy to exit
  frame.delete

frame.idProperties do ():
  discard execCmd("RUNDLL32.EXE PRINTUI.DLL,PrintUIEntry /p /n" & get_default_printer())

frame.idQueue do ():
  discard execCmd("RUNDLL32.EXE PRINTUI.DLL,PrintUIEntry /o /n" & get_default_printer())


frame.wEvent_Menu do (event: wEvent):
  var item = trayMenu.getSubMenu(0).findItem(event.id)
  if item != nil:
    trayMenu.setText(2, item.text)
    SetDefaultPrinter(item.text) # change default printer
  event.skip

frame.wEvent_TrayMove do (event: wEvent): # move mouse over tray
  frame.setTrayIcon(icon, get_default_printer())

frame.wEvent_TrayRightUp do (event: wEvent): # right click on tray icon -> Menu
  update_printer_menu()
  trayMenu.setText(2, get_default_printer())
  frame.popupMenu(trayMenu)

frame.applyDarkModeToWindow(enable=true)
app.mainLoop()
