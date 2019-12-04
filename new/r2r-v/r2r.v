import (
	os
	sync
	time
	term
	filepath
// 	radare.r2
)

pub fn main() {
	println('Loading tests')
	os.chdir('..')
	mut r2r := R2R{}
	r2r.load_tests()
	r2r.run_tests()
}

/////////////////

struct R2R {
mut:
	cmd_tests []R2RTest
//	r2 &r2.R2
	wg sync.WaitGroup
	failed int
	fixed int
	broken int
}

struct R2RTest {
mut:
	name string
	file string
	args string
	source string
	cmds string
	expect string
	expect_err string
	// mutable
	broken bool
	failed bool
	fixed bool
}

fn (test R2RTest) parse_slurp(v string) (string, string) {
	mut res := ''
	mut slurp_token := ''
	if v.starts_with("'") || v.starts_with("'") {
		eprintln('Warning: Deprecated syntax, use <<EOF in ${test.source} @ ${test.name}')
	} else if v.starts_with('<<') {
		slurp_token = v[2 .. v.len]
		if slurp_token == 'RUN' {
			eprintln('Warning: Deprecated <<RUN, use <<EOF in ${test.source} @ ${test.name}')
		}
	} else {
		res = v[0 .. v.len]
	}
	return res, slurp_token
}

fn (r2r mut R2R) load_cmd_test(testfile string) {
	mut test := R2RTest{}
	lines := os.read_lines(testfile) or { panic(err) }
	mut slurp_target := &test.cmds
	mut slurp_token := '' 
	mut slurp_data := ''
	test.source = testfile
	for line in lines {
		if line.len == 0 {
			continue
		}
		if slurp_token.len > 0 {
			if line == slurp_token {
				*slurp_target = slurp_data
				slurp_data = ''
				slurp_token = ''
			} else {
				slurp_data += '${line}\n'
			}
			continue
		}
		kv := line.split_nth('=', 2)
		if kv.len == 0 {
			continue
		}
		match kv[0] {
			'CMDS' {
				if kv.len > 1 {
					a, b := test.parse_slurp(kv[1])
					test.cmds = a
					slurp_token = b
					if slurp_token.len > 0 {
						slurp_target = &test.cmds
					}
				} else {
				 	panic('Missing arg to cmds')
				}
			}
			'EXPECT' {
				if kv.len > 1 {
					a, b := test.parse_slurp(kv[1])
					test.expect = a
					slurp_token = b
					if slurp_token.len > 0 {
						slurp_target = &test.expect
					}
				} else {
				 	panic('Missing arg to cmds')
				}
			}
			'EXPECT_ERR' {
				if kv.len > 1 {
					a, b := test.parse_slurp(kv[1])
					test.expect_err = a
					slurp_token = b
					if slurp_token.len > 0 {
						slurp_target = &test.expect_err
					}
				} else {
				 	panic('Missing arg to cmds')
				}
			}
			'BROKEN' {
				if kv.len > 1 {
					test.broken = kv[1].len > 0 && kv[1] == '1'
				} else {
					println('Warning: Missing value for BROKEN in ${test.source}')
				}
			}
			'ARGS' {
				if kv.len > 0 {
					test.args = line[5 .. line.len]
				} else {
					println('Warning: Missing value for ARGS in ${test.source}')
				}
			}
			'FILE' {
				test.file = line[5 .. line.len]
			}
			'NAME' {
				test.name = line[5 .. line.len]
			}
			'RUN' {
				if test.name.len == 0 {
					println('Invalid test name in ${test.source}')
				} else {
					if test.name == '' {
						panic('invalid test')
					} else {
						if test.file == '' {
							test.file = '-'
						}
						r2r.cmd_tests << test
					}
					test = R2RTest{}
					test.source = testfile
				}
			}
		}
		// println(line)
	}
}

/*
fn (r2r R2R)run_commands(test R2RTest) string {
	res := ''
	for cmd in cmds {
		if isnil(cmd) {
			continue
		}
		res += r2r.r2.cmd(cmd)
	}
	return res
}
*/

fn (r2r mut R2R)run_test(test R2RTest) {
	time_start := time.ticks()
	// eprintln(test)
	tmp_dir := os.tmpdir()
	tmp_script := filepath.join(tmp_dir, 'script.r2')
	tmp_stderr := filepath.join(tmp_dir, 'stderr.txt')
	tmp_output := filepath.join(tmp_dir, 'output.txt')

	os.write_file(tmp_script, test.cmds)
	// TODO: handle timeout
	os.system('radare2 -e scr.utf8=0 -e scr.interactive=0 -e scr.color=0 -NQ -i ${tmp_script} ${test.args} ${test.file} 2> ${tmp_stderr} > ${tmp_output}')
	res := os.read_file(tmp_output) or { panic(err) }

	os.rm(tmp_script)
	os.rm(tmp_output)
	os.rm(tmp_stderr)
	os.rmdir(tmp_dir)

	mut mark := 'OK'
	if res.trim_space() != test.expect.trim_space() {
		//test.failed = true
		r2r.failed++
		if !test.broken {
			println(test.file)
			println(term.ok_message(test.cmds))
			println(term.fail_message(test.expect))
			println(term.ok_message(res))
			mark = 'XX'
			r2r.failed++
		} else {
			mark = 'BR'
			r2r.broken++
		}
	} else {
		if test.broken {
		//	test.fixed = true
			r2r.fixed++
			mark = 'FX'
		}
	}
	time_end := time.ticks()
	times := time_end - time_start
	println('[${mark}] (time ${times}) ${test.source} : ${test.name}')
	// count results
	r2r.wg.done()
}

fn (r2r mut R2R)run_tests() {
	println('Running tests')
	// r2r.r2 = r2.new()
	// TODO: use lock
	r2r.wg = sync.new_waitgroup()
	r2r.wg.add(r2r.cmd_tests.len)
	for t in r2r.cmd_tests {
		// go r2r.run_test(t)
		r2r.run_test(t)
	}
	println('waiting')
	r2r.wg.wait()
	println('waited')

	println('')
	success := r2r.cmd_tests.len - r2r.failed
	println('Broken: ${r2r.broken} / ${r2r.cmd_tests.len}')
	println('Fixxed: ${r2r.fixed} / ${r2r.cmd_tests.len}')
	println('Succes: ${success} / ${r2r.cmd_tests.len}')
	println('Failed: ${r2r.failed} / ${r2r.cmd_tests.len}')
}

fn (r2r mut R2R)load_cmd_tests(testpath string) {
	files := os.ls(testpath) or { panic(err) }
	for file in files {
		f := filepath.join(testpath, file)
		if os.is_dir (f) {
			r2r.load_cmd_tests(f)
		} else {
			r2r.load_cmd_test(f)
		}
	}
}

fn (r2r R2R)load_asm_tests(testpath string) {
	println('TODO: asm tests')
}

fn (r2r mut R2R)load_tests() {
	r2r.cmd_tests = []
	db_path := 'db'
	dirs := os.ls(db_path) or { panic(err) }
	for dir in dirs {
		if dir == 'archos' {
			println('TODO: archos tests')
		} else if dir == 'asm' {
			r2r.load_asm_tests('$(db_path)/$(dir)')
		} else {
			r2r.load_cmd_tests('${db_path}/${dir}')
		}
	}
}
