const { app } = require('@azure/functions');

// NOTE: this counter lives in memory, so it resets whenever the
// function app restarts or scales. Fine for a demo. For a persistent
// count, swap this for Azure Table Storage or Cosmos DB.
let visitorCount = 0;

app.http('VisitorCounter', {
    methods: ['GET'],
    authLevel: 'anonymous',
    handler: async (request, context) => {
        visitorCount++;

        const ip =
            request.headers.get('x-forwarded-for') ||
            request.headers.get('x-client-ip') ||
            request.headers.get('client-ip') ||
            'Unknown';

        return {
            status: 200,
            jsonBody: {
                visitors: visitorCount,
                ip: ip
            }
        };
    }
});
