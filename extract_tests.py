import os, sys

# from rocksdb.tools.db_crashtest import default_params

fdb_test_path = './foundationdb/tests/'

test_params = {
    'general': {},
    'workload': {}
}

def get_fdb_test_params(test_path):
    """
    Get the test parameters from the foundationdb test directory.
    """
    test_files = []
    for root, dirs, files in os.walk(test_path):
        if 'status' in root or 'TestRunner' in root or 'authorization' in root:
            continue
        for file in files:
            if file.endswith('.txt') or file.endswith('.toml'):
                test_files.append(os.path.join(root, file))
    test_files.sort()

    for test in test_files:

        if '\\' in test:
            splitter = '\\'
        else:
            splitter = '/'
        test_file_name = test.split(splitter)[-1]

        with open(test, 'r') as f:
            content = f.readlines()
        if 'CMakeLists.txt' in test:
            continue
        if '.txt' in test:
            # txt Test file
            '''
            testTitle=AsyncFileCorrectnessTest
            general_param1 = xx
            general_param2 = xx
            <general test configs>

                testName=AsyncFileCorrectness
                workload_params=xx
                <test workload configs>
            '''
            try:
                testTitle = content[0].split('=')[1].strip()
            except IndexError:
                print(test, content[0])
            for line in content[1:]:
                try:
                    if line.strip() == '' or '=' not in line:
                        continue
                    if line.startswith('\t') or line.startswith(' '):
                        workload_param, workload_param_val = line.strip().split('=', 1)
                        workload_param = workload_param.strip()
                        workload_param_val = workload_param_val.strip()
                        
                        if workload_param not in test_params['workload']:
                            test_params['workload'][workload_param] = [test_file_name]
                        elif test_file_name not in test_params['workload'][workload_param]:
                                test_params['workload'][workload_param].append(test_file_name)
                    else:
                        general_param, general_param_val = line.strip().split('=', 1)
                        general_param = general_param.strip()
                        general_param_val = general_param_val.strip()

                        if general_param not in test_params['general']:
                            test_params['general'][general_param] = [test_file_name]
                        elif test_file_name not in test_params['general'][general_param]:
                            test_params['general'][general_param].append(test_file_name)
                except ValueError:
                    print(test, line.strip())
                    break

        elif '.toml' in test:
            # toml Test file
            all_content = '\n'.join(content)
            blocks = all_content.split('[[test.workload]]')
            
            general_block = blocks[0].strip()
            for line in general_block.split('\n'):
                line = line.split('#')[0].strip()
                if line.strip() == '' or '=' not in line:
                    continue
                try:
                    general_param, general_param_val = line.strip().split('=', 1)
                    general_param = general_param.strip()
                    general_param_val = general_param_val.strip()

                    if general_param not in test_params['general']:
                        test_params['general'][general_param] = [test_file_name]
                    elif test_file_name not in test_params['general'][general_param]:
                        test_params['general'][general_param].append(test_file_name)
                except ValueError:
                    print(test, line.strip())
                    continue

            workload_blocks = blocks[1:]
            for block in workload_blocks:
                workload_block = block.strip()
                if workload_block == '':
                    continue
                for line in workload_block.split('\n'):
                    line = line.split('#')[0].strip()
                    if line.strip() == '' or '=' not in line:
                        continue
                    try:
                        workload_param, workload_param_val = line.split('=', 1)
                        workload_param = workload_param.strip()
                        workload_param_val = workload_param_val.strip()

                        if workload_param not in test_params['workload']:
                            test_params['workload'][workload_param] = [test_file_name]
                        elif test_file_name not in test_params['workload'][workload_param]:
                                test_params['workload'][workload_param].append(test_file_name)
                    except ValueError as e:
                        print(test, line.strip())
                        continue
                
    
    all_general_params = list(test_params['general'].keys())
    all_general_params.sort()
    test_params['all_general_params'] = all_general_params

    all_workload_params = list(test_params['workload'].keys())
    all_workload_params.sort()
    test_params['all_workload_params'] = all_workload_params
    return test_params


if __name__ == '__main__':
    if len(sys.argv) > 1:
        fdb_test_path = sys.argv[1]

    test_params = get_fdb_test_params(fdb_test_path)
    import json
    with open('test_params.json', 'w') as f:
        json.dump(test_params, f, indent=4)