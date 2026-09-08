#Clase para procesar expresiones para consola si va a usar expresiones de godot use mejor Expression
extends Node
class_name ConsoleExpression

#@export var console_manager : ConsoleManager
#no necesario

##Dice si es un separador
func is_separator(tchar : String) -> bool:
  if tchar in ["+","-","*","//"]:
    return true
  return false

##divide un texto en sus partes ejemplo 1*2/3 ["1","*","2*,"//", "3"]
func tokenize(t : String) -> PackedStringArray:
  var total : PackedStringArray = PackedStringArray()
  #var name: int = 0ar in_quote : bool
  #var scaped : bool
  var buffer : String
  t += " "
  #Aqui añadimos un espacio al final en vez de poner un .append al final para que el último token no sea ignorado
  for ch in t:
    if is_separator(ch):
      if buffer.is_empty():
        continue
      total.append(buffer)
    else:
      buffer += ch
  return total

func _ready() -> void:
  var r := tokenize("1*2/3")
  print(r)