# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "flask>=3.1.3",
# ]
# ///
# Basic webserver for BikeAndWatch to fetch rom data 
from flask import Flask, Response
from pathlib import Path
from base64 import b64encode

app = Flask(__name__)

@app.route('/<string:rom_name>/<int:bank>')
def get_rom_data(rom_name, bank):
    """
    Get the bank (16kB) "bank" from "rom_name" in roms folder.
    """
    rom_path = None
    for f in Path("./roms/").rglob("*"):
        if f.is_file() and rom_name == f.stem:
            rom_path = f
            break

    if rom_path == None:
        return "Rom not found.", 400

    bank_size = 16 * 1024
    rom = open(rom_path, "rb")
    rom.seek(bank * bank_size)

    return Response(b64encode(rom.read(bank_size)), mimetype="text/plain")

@app.route('/boot-rom')
def get_boot_rom():
    """
    Get the boot rom.
    """
    boot_rom_path = Path("./roms/dmg_boot.bin")
    if not boot_rom_path.is_file():
        return "Boot Rom not found.", 400
    
    boot_rom = open(boot_rom_path, "rb")
    return Response(b64encode(boot_rom.read()), mimetype="text/plain")

if __name__ == "__main__":
    app.run(debug=True)