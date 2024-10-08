const { getITSChannelId } = require('./testutils');
const { bcsStructs } = require('../dist/bcs');
const { expect } = require('chai');
describe('BCS', () => {
    it('should decode ITS_V0 object successfully', async () => {
        //const itsV0 =
        const channelId = await getITSChannelId(client, objectIds.itsv0);
    });
});
