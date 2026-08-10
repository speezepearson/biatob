/**
 * ESLint rule to forbid direct access to ._creationTime on Convex documents.
 * Use getCreationTime(doc) helper instead, which handles creationTimeOverride for migrated data.
 */
module.exports = {
  meta: {
    type: "problem",
    docs: {
      description: "Disallow direct access to ._creationTime on Convex documents",
      category: "Best Practices",
      recommended: true,
    },
    messages: {
      noDirectCreationTime:
        "Do not access ._creationTime directly. Use getCreationTime(doc) from convex/helpers.ts instead, which handles creationTimeOverride for migrated data.",
    },
    schema: [],
  },
  create(context) {
    return {
      MemberExpression(node) {
        // Check if accessing ._creationTime property
        if (
          node.property &&
          node.property.type === "Identifier" &&
          node.property.name === "_creationTime"
        ) {
          context.report({
            node,
            messageId: "noDirectCreationTime",
          });
        }
      },
    };
  },
};
