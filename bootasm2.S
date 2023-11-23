# When the PC starts, the processor is essentially emulating an 8086 processor, i.e. 
# a 16-bit processor.  So our initial boot loader code is 16-bit code that will 
# eventually switch the processor into 32-bit mode.

# This code is linked to assume a starting address of 0x7C00 which is where the BIOS
# will load a boot segment.

.code16                         # Assemble for 16-bit mode. This directive ensures the code is treated as 16-bit for real-mode execution.

.globl start                    # Declare 'start' as a global symbol so that it's visible to the linker.

start:
    jmp     real_start          # Jump to the real_start label to begin execution.

real_start:
    movb    %dl, (boot_device)  # Boot device number is passed in DL from BIOS. Save it to 'boot_device' since DL might get overwritten later.

    movw    $boot_message, %si  # Load the address of the 'boot_message' string into SI.
    call    cons_writeline       # Call the 'cons_writeline' routine to print the boot message.

    movw    $booted_from_msg, %si # Load the address of the 'booted_from_msg' string into SI.
    call    cons_write           # Call the 'cons_write' routine to print the "booted from" message.

    movb    (boot_device), %dl  # Reload the boot device number into DL from the 'boot_device' memory location.
    cmp     $0x80, %dl          # Compare DL with 0x80. This checks if the boot device is a hard drive (0x80 and above are hard drives).
    jge     harddrive           # If DL is greater or equal to 0x80, jump to the 'harddrive' label (to handle hard drive specific boot actions).

harddrive:
    movw    $hd, %si                 # Load the address of 'hd' message into SI.
    call    cons_writeline           # Call to display the 'hd' message.
    call    get_starting_sector      # Call routine to get the starting sector from the user.
    call    get_num_sectors          # Call routine to get the number of sectors to read from the user.
    call    read_sectors             # Call routine to read the specified sectors from the disk.
    jmp     endless_loop             # Jump into an endless loop after the operations are complete.

get_starting_sector:
    movw    $prompt_start_sector, %si # Load the address of the 'prompt_start_sector' message into SI.
    call    cons_write               # Display the prompt for starting sector.
    movb    $4, max_input_amount     # Set the maximum input amount to 4 (bytes/characters).
    call    get_input                # Call routine to read user input.
    call    convert_input_to_int     # Call routine to convert the user input to an integer.
    movw    %ax, start_sector        # Store the converted integer in 'start_sector'.

    ret                              # Return from the 'get_starting_sector' routine.
    
get_num_sectors:
    movw    $prompt_num_sectors, %si  # Load the address of 'prompt_num_sectors' message into SI.
    call    cons_write               # Display the prompt for number of sectors.
    movb    $4, max_input_amount     # Set the maximum input amount to 4 (bytes/characters).
    call    get_input                # Call routine to read user input.
    call    convert_input_to_int     # Call routine to convert the user input to an integer.
    movw    %ax, num_sectors         # Store the converted integer in 'num_sectors'.

    ret                              # Return from the 'get_num_sectors' routine.

get_input:
    movw    $input_buffer, %si
    movb    max_input_amount, %cl 
    call    input_loop
    call    cons_write_crlf
    ret

input_loop:
    movb    $0x00, %ah          # BIOS.GetKeyboardKey
    int     $0x16               # -> AX
    
    cmp     $0x0D, %al          # Check for enter key
    je      check_input_length

    cmp     $0x08, %al          # Check for backspace key
    je      handle_backspace

    # Check if we have reached the maximum input amount
    cmp     $0, %cl             # Check if CL is zero
    je      input_loop          # Loop if CL is zero to ignore input unless it's backspace

    # Echo the character back to the user
    movb    $0x0E, %ah          # BIOS.TTYPrint
    int     $0x10               # Display the character in AL
    
    # Store the character and advance pointer
    movb    %al, (%si)
    inc     %si
    
    incb    input_length

    # Decrement our counter (in CL)
    dec     %cl
    
    jmp     input_loop          # Go back to get next character

handle_backspace:
    # Check if SI points to start of input_buffer, if so, no characters to delete
    cmp     $input_buffer, %si  
    je      input_loop

    # Move the cursor back by one space to give the impression of deletion
    movb    $0x0E, %ah          # BIOS.TTYPrint
    movb    $0x08, %al          # ASCII for backspace
    int     $0x10               # Move cursor one space back
    movb    $0x20, %al          # ASCII for space
    int     $0x10               # Print space to clear character
    movb    $0x08, %al          # ASCII for backspace
    int     $0x10               # Move cursor one space back

    # Decrease pointer
    dec     %si
    # Clear the last character from buffer
    movb    $0, (%si)
    
    # Increment our counter
    inc     %cl

    # Decrement the input_length counter if greater than 0
    cmpb    $0, input_length
    jle     input_loop
    decb    input_length
    jmp     input_loop


check_input_length:
    # Compare input_length with 0
    cmpb    $0, input_length
    jne     finish_input        # If input_length is not 0, finish input


    movb    (%si), %al         # Load the current character into AL
    cmpb    $'0', %al          # Compare with ASCII '0'
    jl      invalid_input      # If less, it's not a digit

    cmpb    $'9', %al          # Compare with ASCII '9'
    jg      invalid_input      # If greater, it's not a digit

    # Else, prompt the user to enter a value again
    call    cons_write_crlf
    movw    $prompt_no_input, %si
    call    cons_write
    movw    $input_buffer, %si
    jmp     input_loop


finish_input:
    # Calculate the effective address for null-termination
    movb    $0, (%si)

    # Clear the input_length counter
    movb    $0, input_length

    ret 

input_error:
    movw $prompt_invalid_input, %si   # Load the address of the invalid input prompt
    call cons_writeline               # Display the error message
    jmp input_loop                    # Restart input collection

convert_input_to_int:
    movw    $input_buffer, %si  # Set SI to point to the input buffer
    xor     %ax, %ax            # Clear %ax to store the final integer
    xor     %dx, %dx            # Clear %dx, used for intermediate calculations

convert_loop:
    movb    (%si), %dl          # Load the next byte from the string into %dl
    test    %dl, %dl            # Test if the byte is null (end of string)
    jz      convert_end         # If null, conversion is done
    sub     $'0', %dl           # Convert ASCII to integer (e.g., '3' -> 3)
    imul    $10, %ax            # Multiply current %ax value by 10 (shift left)
    add     %dx, %ax            # Add the new digit to %ax
    inc     %si                 # Move to the next character in the string
    jmp     convert_loop       # Repeat the loop

convert_end:
    ret

invalid_input:
    movw    $prompt_invalid_input, %si   # Load the address of the invalid input prompt
    call    cons_writeline               # Display the error message

    movw    $input_buffer, %si

    jmp     input_loop                    # Restart input collection

cons_write_sector:
    movw    $prompt_current_sector, %si
    call    cons_write
    movw    current_sector, %bx
    call    cons_write_int            # Display the value in %bx
    call    cons_write_crlf
    call    cons_write_crlf
    movw    $disk_address_packet, %si # Point %si to disk_address_packet
    ret

read_sectors:
    xor     %bx, %bx                   # Clear BX register. BX is used later for addressing.
    movw    $128, byte_count            # Set byte_count to 64. This represents the number of bytes to process.
    movw    $16, line_bytes            # Set line_bytes to 16. This is likely the number of bytes per line to display.

    movw    start_sector, %ax          # Load the starting sector number into AX.
    movw    %ax, current_sector        # Store the starting sector number in current_sector.
    call    cons_write_sector          # Call routine to display the current sector.

    movw    start_sector, %ax           # Load the number of sectors to read into AX.
    movw    %ax, 2(%si)       
    
    add     num_sectors, %ax          # Add the starting sector to the number of sectors.
    movw    %ax, total_sectors         # Store the calculated value (start sector + num sectors) into the total_sectors variable.

    movw    $0xD000, 4(%si)            # Set the memory address to read data into as 0xD000.

read_sectors_loop:
    cmp     $0, line_bytes             # Compare line bytes with 0 to check if the end of the line is reached.
    je      read_sectors_continue      # If equal, jump to read_sectors_continue to handle the next line.

    movw    current_sector, %bx        # Load the current sector number into BX.
    movw    %bx, 8(%si)                # Store the current sector number in the disk address packet for LBA addressing.

    movb    $0x42, %ah                 # Set AH to 0x42, selecting the INT 13h BIOS function for LBA disk read.
    movb    (boot_device), %dl         # Load the boot device ID into DL for the disk read function.
    int     $0x13                      # Call BIOS interrupt 0x13 to read from the disk.
    jc      read_failed                # If the carry flag is set, an error occurred; jump to the error handling label.

    movb    (0xD000), %al             # Check that what we loaded is not empty
    cmpb    $0, %al
    je      read_failed

    incw    current_byte               # Increment the current_byte counter, tracking the current byte position.
    decw    byte_count                 # Decrement the byte_count counter, tracking the number of bytes left to process.
    decw    line_bytes                 # Decrement the line_bytes counter, tracking the number of bytes left to display in the current line.

    jmp    read_sectors_loop   # Loop until CX is 0.


read_sectors_continue:
    movw    byte_count, %dx             # Load the value of 'byte_count' into DX.
    cmp     $0, %dx
    je      read_sectors_pause

    jmp     display_line_content       # If CX is 0, jump to display_line_content to output the line.


read_sectors_done:
    call    cons_write_crlf             # Call routine to write a carriage return and line feed (CRLF) to the console.
    movw    $prompt_finished, %si       # Load the address of the 'prompt_finished' message into SI.
    call    cons_writeline              # Call routine to write the 'prompt_finished' message to the console.
    jmp     endless_loop                # Jump to an endless loop, likely to halt the bootloader.
    ret                                 # Return from the routine, though this is likely never reached due to the jump.

read_sectors_pause:
    movw    $prompt_continue, %si       # Load the address of the 'prompt_continue' message into SI.
    call    cons_writeline              # Call routine to write the 'prompt_continue' message to the console.
    call    cons_write_crlf             # Call routine to write another CRLF to the console.
    movw    $disk_address_packet, %si   # Load the address of the 'disk_address_packet' into SI.
    movb    $0x00, %ah                  # Set AH to 0x00 for INT 16h function (keyboard input).
    int     $0x16                       # Call INT 16h to wait for a key press.

    movw    current_byte, %bx           # Load the value of 'current_byte' into BX.
    cmp     $512, %bx                   # Compare BX to 512 (the size of a sector in bytes).
    je      next_sector                 # If equal, jump to 'next_sector' to handle the next sector.

    movw    $128, byte_count            # Set byte_count to 128. This represents the number of bytes to process.

    jmp     read_sectors_loop           # Jump back to the main read loop.

next_sector:
    movw    current_sector, %bx     # Load the current sector number into BX.
    movw    total_sectors, %ax      # Load the total number of sectors into AX.
    cmpw    %ax, %bx               # Compare the current sector with the end sector (start sector + number of sectors).
    je      read_sectors_done      # If the current sector is greater or equal, all sectors have been processed; jump to completion.
    
    incw    current_sector         # Increment the current_sector counter.
    call    cons_write_sector      # Call routine to display the current sector number.
    movw    $0, current_byte       # Reset current_byte to 1, starting the new sector.
    movw    $16, %cx                # Reset line_bytes to 16, preparing for the new sector.
    
    movw    $128, byte_count            # Set byte_count to 128. This represents the number of bytes to process

    jmp     read_sectors_loop      # Jump back to the main read sectors loop.

read_failed:
    xor     %si, %si               # Clear SI register.
    movw    $prompt_disk_error, %si # Load the address of the disk error prompt into SI.
    call    cons_write             # Display the disk error message.
    xor     %bx, %bx               # Clear BX register.
    movb    %ah, %bl               # Move the error code (in AH) to BL for display.

    movw    $4, %cx                # Set CX to 4, indicating the number of bytes for the error code display.
    call    cons_write_hex         # Call subroutine to print the error code in hexadecimal.
    call    cons_write_crlf        # Call routine to write a carriage return and line feed (CRLF) to the console.
    
    call    get_starting_sector
    call    get_num_sectors

    jmp     read_sectors
    ret

display_line_content:

    cmp     $0, byte_count             # Compare byte_count with 0 to check if the end of the line is reached.
    je      read_sectors_loop               # If equal, jump to read_sectors_loop to handle the next sector.

    movw    4(%si), %di            # Load the memory address to read from (stored at 4(%si)) into DI.

    movw    current_byte, %bx      # Load the current_byte value into bx.
    subw    $16, %bx              # Subtract 16 from bx to calculate the offset.
    add     %bx, %di               # Add the offset to bx.
    
    # Display the offset in hexadecimal.
    movw    $4, %cx                # Set CX to 4, indicating the number of bytes for the offset display.
    call    cons_write_hex         # Call subroutine to display the offset in hexadecimal.
    movb    $0x20, %al             # Load the ASCII code for space into AL.
    call    cons_write_char           # Call routine to display a space character.


    xor     %bx, %bx               # Clear BX.
    movw    $16, line_bytes              # Reset DX to 16, preparing for the next line.

display_hex_line_loop:
    movw   line_bytes, %cx          # Load the number of bytes to display into DX.
    cmp    $0, %cx                # Compare DX with 0 to check if the end of the line is reached.
    je     display_hex_done         # If DX is 0, jump to display_hex_done, indicating the end of the hexadecimal line display.

    movw    $2, %cx             # Set CX to 2 (number of bytes to display)
    xor     %bh, %bh      # Clear the high byte of BX
    movb    (%di), %al       # Move lower byte of DI to AL
    movb    %al, %bh       # Move AL to BH
    call    cons_write_hex      # Display the byte in AL as a 2-digit hex value

    movb    $0x20, %al             # Load the ASCII code for space into AL.
    call    cons_write_char           # Call routine to display a space character.

    inc    %di                      # Increment DI to move to the next byte in memory.
    decw   line_bytes                     # Decrement DX, counting down the number of bytes to display in this line.
    jmp    display_hex_line_loop    # Loop back to continue displaying the line in hexadecimal.

display_hex_done:
    movw    $16, line_bytes
    subw    $16, %di

display_ascii_line_loop:
    movw   line_bytes, %cx          # Load the number of bytes to display into DX.
    cmp    $0, %cx                  # Compare CX with 0 to check if the end of the line is reached.
    je     display_line_done        # If CX is 0, jump to display_line_done, indicating the end of the ASCII line display.

    movb    (%di), %al       # Move lower byte of DI to AL
    cmpb    $32, %al       # Compare AL with 32
    jl     cons_write_underscore     # If AL >= 32, jump to display

    call    cons_write_char   # Display the character in AL

    decw   line_bytes                     # Decrement DX, counting down the number of bytes to display in this line.
    inc    %di                      # Increment DI to move to the next byte in memory.
    jmp    display_ascii_line_loop  # Repeat the loop 


display_line_done:
    call    cons_write_crlf
    movw    $16, line_bytes    # Reset the line_bytes counter
    movw    $disk_address_packet, %si
    jmp     read_sectors_loop
    ret

endless_loop:                   # Loop forever more
    jmp     endless_loop   


debug:
    movw  4(%si), %di            # Load the memory address to read from (stored at 4(%si)) into DI.
    movw  $16, %cx               # Set CX to 16, indicating the number of bytes for the offset display.
    call  cons_write_hex         # Call subroutine to display the offset in hexadecimal.

    movw    $disk_address_packet, %si
    movb    $0x00, %ah                  # Set AH to 0x00 for INT 16h function (keyboard input).
    int     $0x16                       # Call INT 16h to wait for a key press.
    jmp     read_sectors_loop


cons_write_char:
    movb    $0x0e, %ah          # Output the character in AL to the screen
    int     $0x10
    ret

    
cons_write_underscore:
    movb    $95, %al       # Otherwise, load ASCII code for underscore into AL
    call    cons_write_char   # Display the character in AL

    decw   line_bytes                     # Decrement DX, counting down the number of bytes to display in this line.
    inc    %di                      # Increment DI to move to the next byte in memory.

    jmp     display_ascii_line_loop  # Repeat the loop

# Write to the console using BIOS.
# 
# Input: SI contains the address of the null-terminated string to be displayed

cons_write:
    movb    $0x0e, %ah           # 0x0e is the INT 10h BIOS call to output the value contained in AL to screen

cons_write_rpt:
    movb    (%si), %al          # Load the byte at the location contained in the SI register into AL   
    inc     %si                 # Add 1 to the value in SI
    cmp     $0, %al             # Compare the value in AL with 0
    jz      cons_write_done     # If it is zero, then we are done
    int     $0x10               # Output the character in AL to the screen
    jmp     cons_write_rpt      # and continue

cons_write_done:                # Something that is called will never return 
    ret                         # until a 'ret' instruction is encountered.  Labels do 
                                # not give a program any structure.  They just give a 
                                # memory location a name that we can use in our code.
cons_write_crlf:
    movb    $0x0e, %ah          # Output CR
    movb    $0x0d, %al
    int     $0x10
    movb    $0x0a, %al          # Output LF
    int     $0x10
    ret

cons_writeline:
    call    cons_write
    call    cons_write_crlf
    ret

# Output the 16-bit value in BX to the screen as a 4 digit hex value	
#
# Input:  BX = Value to output	

HexChars:	.ascii "0123456789ABCDEF"

cons_write_hex:
    movb    $0x0E, %ah
	
hexloop:
    rol     $4, %bx # Rotate left by 4 bits
    movw    %bx, %si # Move the value in BX into SI
    and     $0x000F, %si # Mask the lower 4 bits
    movb    HexChars(%si), %al # Move the value in HexChars into AL
	int		$0x10 # Call BIOS to display character
	loop	hexloop # Repeat the loop
	ret


# Output the value in BX as an unsigned integer
#
# Input: BX = Value to output
	
cons_write_int:
    movw    $IntBuffer + 4, %si
    movw    %bx, %ax
	
getdigit:
	xor		%dx, %dx
	movw	$10, %cx
	div		%cx
	addb	$48, %dl
	movb	%dl, (%si)
	dec		%si
	cmp		$0, %ax
	jne		getdigit
	inc		%si
	call	cons_write
	ret


# Format of disk address packet
#
# Offset	Size	Description
#  0          1     size of packet (16 bytes)
#  1          1     always 0
#  2          2     number of sectors to transfer (max 127 on some BIOSes)
#  4          4     transfer buffer (first 2 bytes is 16-bit offset, next 2 bytes is 16 bit segment)
#  8          4     lower 32-bits of 48-bit starting LBA (starting from 0)
#  12         4     upper 16-bits of 48-bit starting LBA (will always be 0 for us)


disk_address_packet:
    .byte   0x10
    .byte   0
    .word   0
    .long   0
    .long   0
    .long   0

# ... data section ...

prompt_start_sector: .string "Enter starting sector (4 Digits): "
prompt_num_sectors: .string "Enter number of sectors (4 Digits): "
prompt_no_input: .string "No input detected. Please try again: "
prompt_current_sector: .string "Current sector: "
IntBuffer:   .string "     "
prompt_disk_error: .string "Disk read error occurred. Error code: "
prompt_invalid_input: .string "Invalid input. Please try again."
prompt_continue: .string "Press any key to continue..."
debug_msg: .string "Returned from input loop."
prompt_finished: .string "Finished reading sectors."

start_sector: .word 0x0000 # Allocates 2 bytes, initialized to 0
line_bytes: .word 0x0000 # Allocates 2 bytes, initialized to 0
current_byte: .word 0x0000  
byte_count: .word 0x0000  
num_sectors: .word 0x0000 # Allocates 2 bytes, initialized to 0
current_sector: .word 0x0000 # Allocates 2 bytes, initialized to 0
total_sectors: .word 0x0000 # Allocates 2 bytes, initialized to 0

input_buffer: .space 5, 0
max_input_amount: .byte 0
input_length: .byte 0

# Program data

boot_device:
    .byte   0

boot_message:     
    .string "Boot Loader Stage 2 loaded"             
booted_from_msg:
    .string "Booting from "
fd: .string "floppy disk"
hd: .string "hard drive"

