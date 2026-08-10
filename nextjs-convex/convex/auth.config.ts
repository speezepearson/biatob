export default {
  providers: [
    {
      domain: process.env.AUTH_DOMAIN ?? "http://localhost:3000",
      applicationID: "convex",
    },
  ],
};
