#! /bin/bash

BIN=./compiler.exe
EXTRACT=./extract.sh
NB_ERR="0"
NB_OUT="0"
NB_MOD="0"
NB_STR="0"
NB_LIQ="0"
NB_EXT="0"

process () {
    printf '%-50s' $1
    REF=$i.ref
    $BIN -P $i > $REF 2> /dev/null
    RET=`echo $?`
    if [ ${RET} -eq 0 ]; then
	      echo -ne "\033[32m OK \033[0m"

        OUT=$i.out
        $BIN -PP $i | $BIN -P > $OUT 2> /dev/null
        RET=`echo $?`
        if [ ${RET} -eq 0 ]; then
    	      echo -ne "     \033[32m OK \033[0m"

            cmp $REF $OUT > /dev/null 2> /dev/null
            RET=`echo $?`
            if [ ${RET} -eq 0 ]; then
    	          echo -ne "     \033[32m OK \033[0m"
            else
	              echo -ne "     \033[31m KO \033[0m"
                NB_OUT=$((${NB_OUT} + 1))
            fi
        else
	          echo -ne "     \033[31m KO \033[0m"
            NB_OUT=$((${NB_OUT} + 1))
        fi
        echo ""
    else
	      echo -ne "\033[31m KO \033[0m"
	      echo -e "    \033[31m KO \033[0m"
        NB_ERR=$((${NB_ERR} + 1))
        NB_OUT=$((${NB_OUT} + 1))
    fi
    rm -f $OUT $REF
}

printf '%-48s%s\n' '' '  PARSE   REPARSE   SAME'

for i in contracts/*.arl; do
  process $i
done

echo ""
for i in tests/*.arl; do
  process $i
done

echo ""
for i in extensions/*.arlx; do
  process $i
done

echo ""

if [ ${NB_ERR} -eq 0 ]; then
    echo "all arl[x] files compile."
else
    echo -e "\033[31mErrors of parse: ${NB_ERR} \033[0m"
fi

if [ ${NB_OUT} -eq 0 ]; then
    echo "all generated print files compile."
else
    echo -e "\033[31mErrors of print : ${NB_OUT} \033[0m"
fi