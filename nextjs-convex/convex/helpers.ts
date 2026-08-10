/**
 * Helper functions for Convex document operations.
 *
 * IMPORTANT: Always use getCreationTime() instead of accessing _creationTime directly.
 * This ensures proper handling of migrated data that may have creationTimeOverride set.
 */

/**
 * Get the creation time of a document, preferring creationTimeOverride if set.
 * This is needed because migrated documents have their original creation time
 * stored in creationTimeOverride, while _creationTime reflects when they were
 * imported into Convex.
 *
 * @param doc - A Convex document with _creationTime and optional creationTimeOverride
 * @returns The creation timestamp in milliseconds
 */
export function getCreationTime(
  doc: { _creationTime: number; creationTimeOverride?: number }
): number {
  return doc.creationTimeOverride ?? doc._creationTime;
}
