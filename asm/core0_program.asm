# Core 0 end-to-end pipeline test.
addi $s0, $zero, 0x0300
addi $t0, $zero, 5
addi $t1, $t0, 3
add  $t2, $t1, $t0
sw   $t2, 0($s0)
lw   $t3, 0($s0)
add  $t4, $t3, $t0
beq  $t4, $t4, branch_taken
addi $t5, $zero, 99
addi $t5, $zero, 88
branch_taken:
addi $t5, $zero, 7
j    jump_target
addi $t6, $zero, 99
jump_target:
addi $t6, $zero, 9
addi $s1, $zero, 0x0340
sw   $t4, 0($s1)
lw   $t7, 0($s1)
addi $s2, $zero, 1
done:
j done
