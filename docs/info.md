<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project primarily uses the input pins, the following is what each input pin does: 
ui_in[0] - Night-Cycle 
ui_in[1] - Waning Crescent 
ui_in[2] - Third Quarter 
ui_in[3] - Waning Gibbous 
ui_in[4] - Full Moon 
ui_in[5] - Waxing Gibbous 
ui_in[6] - First Quarter 
ui_in[7] - Waxing Crescent

The output prioritizes the latter switches (i.e. if both ui_in[2] and ui_in[5] are on, it will output ui_in[5])

## How to test

Tba

## External hardware

N/A
