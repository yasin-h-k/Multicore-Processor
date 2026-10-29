# Core 1 runs concurrently at an independent data address.
addi $s0, $zero, 0x0380
ori  $t0, $zero, 0x00f0
sw   $t0, 0($s0)
lw   $t1, 0($s0)
sub  $t2, $t1, $t0
bne  $t2, $zero, wrong_path
addi $t3, $zero, 11
j    finish
wrong_path:
addi $t3, $zero, 99
finish:
addi $s2, $zero, 1
done:
j done
