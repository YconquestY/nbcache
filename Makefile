.DEFAULT_GOAL := all
BUILD_DIR=build
BINARY_NAME=Beveren #Beveren_nested
BSC_FLAGS=--aggressive-conditions --show-schedule -vdir $(BUILD_DIR) -bdir $(BUILD_DIR) -simdir $(BUILD_DIR) #--show-range-conflict 

.PHONY: clean all $(BINARY_NAME)

$(BINARY_NAME):
	mkdir -p $(BUILD_DIR)
	bsc $(BSC_FLAGS) -o $@ -sim -g mk$@ -u $@.bsv
	bsc $(BSC_FLAGS) -o $@ -sim -e mk$@

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(BINARY_NAME)
	rm -f *.so
	rm -f *.sched

all: clean $(BINARY_NAME)

submit:
	make all
	./Beveren 2>&1 | tee output_submit1.txt 
	./Beveren_nested 2>&1 | tee output_submit2.txt 
	cat output_submit1.txt  output_submit2.txt  | tee output_submit.txt
	git add -A
	git commit -am "Save Changes & Submit"
	git push
