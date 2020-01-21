#========================================================================
#
#                      Default Printer Changer
#                (c) Copyright 2019 Duncan Clarke
#
#========================================================================

# icon resource file
# windres ln_checker.rc ln_checker.o --target=pe-i386
{.link: "printer_changer.o".}

import
  wNim,
  winim/lean,
  winim/inc/winspool,
  osproc,
  algorithm

type
  # A menu ID in wNim is type of wCommandID (distinct int) or any enum type.
  MenuID = enum
    idExit = wIdUser, idProperties, idQueue

proc get_default_printer(): string = # get the default printer
  var needed: DWORD
  GetDefaultPrinter(nil, &needed)
  var buffer = newWString(int needed)
  GetDefaultPrinter(&buffer, &needed)
  return $(buffer)[0 .. ^2] # trim trailing null character

# load icons
const exit = staticRead(r"icons/quit.ico") 
let exitBitmap = Bitmap(Image(exit).scale(16, 16))

const printer = staticRead(r"icons/printer.ico")
let printerBitmap = Bitmap(Image(printer).scale(16, 16))

const ico = staticRead(r"icons/printer.ico")
let icon = Icon(ico)

var app = App()

var frame = Frame()
frame.icon = icon
frame.setTrayIcon(icon)

# menu to change default printer
var menuDefaultPrinter = Menu()
menuDefaultPrinter.append(idProperties, "Properties", "Default Printer Properties")
menuDefaultPrinter.append(idQueue, "Queue", "Default Printer Properties")

# menu for when you right click on tray icon
var trayMenu = Menu() 
trayMenu.appendSeparator()
trayMenu.appendSubMenu(menuDefaultPrinter, get_default_printer(), "Default Printer")
trayMenu.appendSeparator()
trayMenu.append(idExit, "E&xit", "Exit the program.", exitBitmap)

# iterate over local printers and network printers we've made a connection to
var menuPrinters = Menu()
var needed, returned: DWORD
EnumPrinters(PRINTER_ENUM_CONNECTIONS or PRINTER_ENUM_LOCAL, nil, 1, nil, 0, &needed, &returned)
var buffer = newString(needed)
let pInfo = cast[LPBYTE](&buffer)
let printers = cast[ptr UncheckedArray[PRINTER_INFO_1]](pInfo)
EnumPrinters(PRINTER_ENUM_CONNECTIONS or PRINTER_ENUM_LOCAL, nil, 1, pInfo, needed, &needed, &returned)

var printer_names: seq[string]
for i in 0..<returned:
  printer_names.add($(printers[i].pName))
printer_names.sort()

for i in 0..<returned:
  menuPrinters.appendRadioItem(wCommandID i, printer_names[i], printer_names[i])  
  
# insert sub menu containing printers
trayMenu.insertSubMenu(0, menuPrinters, "Set Printer", "Change Default Printer.", printerBitmap)

proc update_printer_menu(): void = # check default printer and mark it checked
  var default = get_default_printer()
  for i in trayMenu.getSubMenu(0):
    if $(i.text) == default:
      i.check()

frame.idExit do ():
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

app.mainLoop()
