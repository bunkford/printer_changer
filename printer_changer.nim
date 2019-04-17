#========================================================================
#
#                         LN CHECKER 
#                (c) Copyright 2019 Duncan Clarke
#
#
#  This program checks LN every five minutes for production orders that:
#  
#  1. Completed but have outstanding material issued or recieved.
#  2. Fully delivered, but order is still active.
#
#========================================================================

# icon resource file
# windres ln_checker.rc ln_checker.o --target=pe-i386
{.link: "printer_changer.o".}
  


import
  wNim,
  winim/lean,
  winim/inc/winspool

type
  # A menu ID in wNim is type of wCommandID (distinct int) or any enum type.
  MenuID = enum
   idExit

proc get_default_printer(): string = # get the default printer
  var needed: DWORD
  GetDefaultPrinter(nil, &needed)
  var buffer = newWString(int needed)
  GetDefaultPrinter(&buffer, &needed)
  return $(buffer)[0 .. ^2] # trim trailing null character

# load icons
const exit = staticRead(r"icons/quit.ico") 
let exitBmp = Bmp(Image(exit).scale(16, 16))

const printer = staticRead(r"icons/printer.ico")
let printerBmp = Bmp(Image(printer).scale(16, 16))

const ico = staticRead(r"icons/printer.ico")
let icon = Icon(ico)

var app = App()

var frame = Frame()
frame.icon = icon
frame.setTrayIcon(icon)

# menu for when you right click on tray icon
var trayMenu = Menu() 
trayMenu.appendSeparator()
trayMenu.append(idExit, "E&xit", "Exit the program.", exitBmp)

# iterate over local printers and network printers we've made a connection to
var menuPrinters = Menu()
var needed, returned: DWORD
EnumPrinters(PRINTER_ENUM_CONNECTIONS or PRINTER_ENUM_LOCAL, nil, 1, nil, 0, &needed, &returned)
var buffer = newString(needed)
let pInfo = cast[LPBYTE](&buffer)
let printers = cast[ptr UncheckedArray[PRINTER_INFO_1]](pInfo)
EnumPrinters(PRINTER_ENUM_CONNECTIONS or PRINTER_ENUM_LOCAL, nil, 1, pInfo, needed, &needed, &returned)
for i in 0..<returned:
  menuPrinters.appendRadioItem(i, $(printers[i].pName), $(printers[i].pName))  
  
# insert sub menu containing printers
trayMenu.insertSubMenu(0, menuPrinters, "Set Printer", "Change Default Printer.", printerBmp)

proc update_printer_menu(): void = # check default printer and mark it checked
  var default = get_default_printer()
  for i in trayMenu.getSubMenu(0):
    if $(i.text) == default:
      i.check()

frame.idExit do ():
  frame.delete

frame.wEvent_Menu do (event: wEvent):
  var item = trayMenu.getSubMenu(0).findItem(event.id)
  if item != nil:
    SetDefaultPrinter(item.text) # change default printer
    echo "Printer set to: " & item.text
  event.skip
  
frame.wEvent_TrayRightUp do (event: wEvent): # right click on tray icon -> Menu
  update_printer_menu()
  frame.popupMenu(trayMenu)
  event.skip

app.mainLoop()
