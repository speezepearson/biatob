/* eslint-disable */
/**
 * Generated utilities for implementing server-side Convex query and mutation functions.
 * This is a stub file that will be replaced by actual generated code when `npx convex dev` runs.
 */

import {
  QueryCtx as BaseQueryCtx,
  MutationCtx as BaseMutationCtx,
  ActionCtx as BaseActionCtx,
  DatabaseReader as BaseDatabaseReader,
  DatabaseWriter as BaseDatabaseWriter,
  queryGeneric,
  internalQueryGeneric,
  mutationGeneric,
  internalMutationGeneric,
  actionGeneric,
  internalActionGeneric,
  httpActionGeneric,
} from "convex/server";
import { DataModel } from "./dataModel";

export type QueryCtx = BaseQueryCtx<DataModel>;
export type MutationCtx = BaseMutationCtx<DataModel>;
export type ActionCtx = BaseActionCtx;
export type DatabaseReader = BaseDatabaseReader<DataModel>;
export type DatabaseWriter = BaseDatabaseWriter<DataModel>;

// Export function builders - using generic versions for stub
export const query = queryGeneric;
export const internalQuery = internalQueryGeneric;
export const mutation = mutationGeneric;
export const internalMutation = internalMutationGeneric;
export const action = actionGeneric;
export const internalAction = internalActionGeneric;
export const httpAction = httpActionGeneric;
