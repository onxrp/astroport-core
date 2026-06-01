import codegen from '@cosmwasm/ts-codegen';
import fs from 'fs';

const directories = await fs.promises.readdir('./schemas');
const contracts = directories.map((dir) => {
  const name = dir.split('-').map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join('');
  return {
    name: name,
    dir: `./schemas/${dir}`
  };
});

codegen({
  contracts,
  outPath: './typescript/',

  // options are completely optional ;)
  options: {
    bundle: {
      enabled: true,
      bundleFile: 'index.ts',
      scope: 'Astroport'
    },
    types: {
      enabled: true
    },
    client: {
      enabled: true,
      execExtendsQuery: false,
    },
    reactQuery: {
      enabled: true,
      optionalClient: true,
      version: 'v4',
      mutations: true,
      queryKeys: true,
      queryFactory: true,
    },
    recoil: {
      enabled: false,
    },
    messageComposer: {
      enabled: false,
    },
    messageBuilder: {
      enabled: false,
    },
    useContractsHook: {
      enabled: false
    }
  }
}).then(() => {
  console.log('✨ all done!');
});
